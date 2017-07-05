***********************************************************
* Newline Call

NewLine     LDY    #c_isNewln      ;Adjust newline status for open file
            LDA    (parm),Y        ;on or off?
            LDX    fcbPtr          ;It will be zero if off
            STA    fcb+fcbNLMask,X ;Set new line mask 
            INY
            LDA    (parm),Y        ; & move in new 'new-line' byte
            STA    fcb+fcbNewLin,X
            CLC
            RTS                    ;No error possible

GetInfo     JSR    FindFile        ;Look for file they want to know about
            BCC    :1              ;Branch if no errors
            CMP    #badPathSyntax  ;Was it a root directory file?
            SEC                    ;(in case of no match)
            BNE    :Ret
            LDA    #$F0
            STA    d_file+d_stor   ;For get info, report proper storage type
            STZ    reqL            ;Force a count of free blocks
            STZ    reqH

            LDX    vcbPtr
            JSR    TakeFreeCnt     ;Take a fresh count of free blocks on this volume
            LDX    vcbPtr
            LDA    vcb+vcbFreeBlks+1,X;Return total blocks and total in use
            STA    reqH            ;First transfer 'free' blocks to zpage for later subtract
            LDA    vcb+vcbFreeBlks,X; to determine the 'used' count
            STA    reqL

            LDA    vcb+vcbTotBlks+1,X;Transfer to 'd_' table as auxID
            STA    d_file+d_auxID+1;(total block count is considered auxID for the volume)
            PHA
            LDA    vcb+vcbTotBlks,X
            STA    d_file+d_auxID

            SEC                    ;Now subtract and report the number of blocks 'in use'
            SBC    reqL
            STA    d_file+d_usage
            PLA
            SBC    reqH
            STA    d_file+d_usage+1

:1          LDA    d_file+d_stor   ;Transfer bytes from there internal order
            LSR                    ; to call spec via 'infoTabl' translation table
            LSR
            LSR                    ; but first change storage type to
            LSR                    ; external (low nibble) format
            STA    d_file+d_stor

            LDY    #c_creTime+1    ;Index to last of user's spec table
:CpyLoop    LDA    InfoTabl-3,Y
            AND    #$7F            ;Strip bit used by setinfo
            TAX
            LDA    d_file,X        ;Move directory info to call spec. table
            STA    (parm),Y
            DEY
            CPY    #c_attr         ;have all info bytes been sent?
            BCS    :CpyLoop
:Ret        RTS

SetInfo     JSR    FindFile        ;Find what user wants...
            BCS    SInfoErr        ;Return any failure

            LDA    BUBit           ;Discover if backup bit can be cleared
            EOR    #backupNeeded
            AND    d_file+d_attr
            AND    #backupNeeded
            STA    bkBitFlg        ; or preserve current...

            LDY    #c_modTime+1    ;Init pointer to user supplied list
:loop1      LDX    InfoTabl-3,Y    ;Get index into coresponding 'd_' table
            BMI    :11             ;Branch if we've got a non-setable parameter
            LDA    (parm),Y
            STA    d_file,X
:11         DEY                    ;Has user's request been satisfied?
            CPY    #c_attr
            BCS    :loop1          ;No, move next byte

* Make sure no illegal access bits were set!

            AND    #$FF-destroyEnable-renameEnable-backupNeeded-fileInvisible-writeEnable-readEnable
            BEQ    SetInfo3        ;Branch if legal access
            LDA    #invalidAccess  ;Otherwise, refuse to do it
            SEC                    ;Indicate error
SInfoErr    RTS

SetInfo3    LDY    #c_modDate+1
            LDA    (parm),Y        ;Was clock null input?
            BEQ    :Jump
            JMP    ReviseDirZ      ;End by updating directory
:Jump       JMP    ReviseDir       ;Update with clock also...

*-------------------------------------------------
* RENAME call
* Only the final name in the path specification
* may be renamed. In other words, the new name
* must be in the same DIRectory as the old name.

Rename      JSR    LookFile        ;Look for source (original) file
            BCC    Rename0         ;Branch if found
            CMP    #badPathSyntax  ;Trying to rename a volume?
            BNE    :1              ;No, return other error
            JSR    RenamePath      ;Syntax new name
            BCS    :1

            LDY    pathBuf         ;Find out if only rootname for new name
            INY
            LDA    pathBuf,Y       ;Must be $ff if v-name only
            BNE    RenBadPath      ;Branch if not single name

            LDX    vcbPtr          ;Test for open files before changing
            LDA    vcb+vcbStatus,X
            BPL    RenameVol       ;Branch if volume not busy
            LDA    #fileBusy
:1          SEC
            RTS

RenameVol   LDY    #$00            ;Get newname's length
            LDA    pathBuf,Y
            ORA    #$F0            ;(root file storage type)
            JSR    MovRootName     ;Update root directory
            BCS    RenErr

            LDY    #$00
            LDX    vcbPtr          ;Update VCB also
:loop       LDA    pathBuf,Y       ;Move new name to VCB
            BEQ    :ExitLoop
            STA    vcb,X
            INY                    ;Bump to next character
            INX
            BNE    :loop           ;Branch always taken
:ExitLoop   CLC                    ;No errors
            RTS

Rename0     JSR    GetNamePtr      ;Set Y-reg to first char of path, X=0
:loop1      LDA    pathBuf,Y       ;Move original name to genBuf
            STA    genBuf,X        ; for later comparison with new name
            BMI    :11             ;Branch if last character has been moved
            INY                    ;Otherwise, get the next one
            INX
            BNE    :loop1          ;Branch always taken

:11         JSR    RenamePath      ;Get new name syntaxed
            BCS    RenErr
            JSR    GetNamePtr      ;Set Y to path, X to 0
            LDA    pathBuf,Y       ;Now compare new name with old name
:loop2      CMP    genBuf,X        ; to make sure that they are in the same dir
            PHP                    ;Save result of compare for now
            AND    #$F0            ;Was last char really a count?
            BNE    :12             ;Branch if not
            STY    rnPtr           ;Save pointer to next name, it might be the last
            STX    pnPtr
:12         PLP                    ;What was the result of the compare?
            BNE    NoMatch         ;Branch if different character or count
            INX                    ;Bump pointers
            INY
            LDA    pathBuf,Y       ;Was that the last character?
            BNE    :loop2          ;Branch if not
            CLC                    ;No-operation, names were the same
            RTS

NoMatch     LDY    rnPtr           ;Index to last name in the chains
            LDA    pathBuf,Y       ;Get last name length
            SEC
            ADC    rnPtr
            TAY
            LDA    pathBuf,Y       ;This byte should be $00!
            BNE    RenBadPath      ;Branch if not

            LDX    pnPtr           ;Index to last of original name
            LDA    genBuf,X
            SEC
            ADC    pnPtr
            TAX
            LDA    genBuf,X        ;This byte should also be $00
            BEQ    GoodNames       ;Continue processing if it is

RenBadPath  LDA    #badPathSyntax
RenErr      SEC
            RTS                    ;Report error

GoodNames   JSR    LookFile        ;Test for duplicate file name
            BCS    :21             ;Branch if file not found, which is what we want!
            LDA    #dupPathname    ;New name already exists
            SEC                    ;Report duplicate
            RTS

:21         CMP    #fileNotFound   ;Was it a valid "file not found"?
            BNE    RenErr          ;No, return other error code
            JSR    SetPath         ;Now syntax the pathname of the file to be changed
            JSR    FindFile        ;Get all the info on this one
            BCS    RenErr

            JSR    TestOpen        ;Don't allow rename to occur if file is in use
            LDA    #fileBusy       ;Anticipate error
            BCS    RenErr
            LDA    d_file+d_attr   ;Test bit that says it's ok to rename
            AND    #renameEnable
            BNE    Rename8         ;Branch if it's alright to rename
            LDA    #invalidAccess  ;Otherwise report illegal access
RenErr1     SEC
            RTS

Rename8     LDA    d_file+d_stor   ;Find out which storage type
            AND    #$F0            ;Strip off name length
            CMP    #directoryFile*16;Is it a directory?
            BEQ    :31
            CMP    #{tree+1}*16    ;Is it a seed, sapling, or tree?
            BCC    :31
            LDA    #badFileFormat
            BNE    RenErr1

:31         JSR    RenamePath      ;Well... since both names would go into the dir,
            BCS    RenErr          ; re-syntax the new name to get local name address

            LDY    rnPtr           ;(Y contains index to local name length)
            LDX    pathBuf,Y       ;Adjust Y to last char of new name
            TYA
            ADC    pathBuf,Y
            TAY
:loop       LDA    pathBuf,Y       ;Move local name to dir entry workspace
            STA    d_file+d_stor,X
            DEY
            DEX
            BNE    :loop

            LDA    d_file+d_stor   ;Preserve file storage type
            AND    #$F0            ;Strip off old name length
            TAX
            ORA    pathBuf,Y       ;Add in new name's length
            STA    d_file+d_stor
            CPX    #directoryFile*16; that file must be changed also
            BNE    RenameDone      ;Branch if not directory type

* Renaming a DIR file

            LDA    d_file+d_first  ;Read in 1st (header) block of sub-dir
            LDX    d_file+d_first+1
            JSR    RdBlkAX
            BCS    RenErr          ;Report errors

            LDY    rnPtr           ;Change the header's name to match the owner's new name
            LDA    pathBuf,Y       ;Get local name length again
            ORA    #$E0            ;Assume it's a vol/subdir header
            JSR    MovRootName
            BCS    RenErr
RenameDone  JMP    ReviseDirZ      ;End by updating all path directories

MovRootName LDX    #$00
:loop       STA    genBuf+4,X
            INX
            INY
            LDA    pathBuf,Y
            BNE    :loop
            JMP    WrtGBuf         ;Write changed header block

*-------------------------------------------------

RenamePath  LDY    #c_newPath      ;Get address to new pathname
            LDA    (parm),Y
            INY
            STA    tPath
            LDA    (parm),Y        ;Set up for syntaxing routine (SynPath)
            STA    tPath+1
            JMP    SynPath         ;Go syntax it. (Ret last local name length in Y)

GetNamePtr  LDY    #$00            ;Return pointer to first name of path
            BIT    prfxFlg         ;Is this a prefixed name?
            BMI    :1              ;Branch if not
            LDY    NewPfxPtr
:1          LDX    #$00
            RTS

***********************************************************
* Destroy Call

Destroy     JSR    FindFile        ;Look for file to be wiped out
            BCS    DstryErr        ;Pass back any error
            JSR    TestOpen        ;Is this file open?
            LDA    totEnt
            BNE    :3              ;Branch if file open

            STZ    reqL            ;Force proper free count in volume
            STZ    reqH            ;(no disk access occurs if already proper)
            JSR    TestFreeBlk
            BCC    :1
            CMP    #volumeFull     ;Was it just a full disk?
            BNE    DstryErr        ;Nope, report error

:1          LDA    d_file+d_attr   ;Make sure it's ok to destroy this file
            AND    #destroyEnable
            BNE    :2              ;Branch if ok
            LDA    #invalidAccess  ;Tell user it's not kosher
            JSR    SysErr          ;(returns to caller of destroy)

:2          LDA    DevNum          ;Before going thru deallocation,
            JSR    TestWrProtZ     ; test for write protected hardware
            BCS    DstryErr
            LDA    d_file+d_first  ;"DeTree" needs first block addr
            STA    firstBlkL       ; which is file's keyblk
            LDA    d_file+d_first+1
            STA    firstBlkH
            LDA    d_file+d_stor   ;Find out which storage type
            AND    #$F0            ;Strip off name length
            CMP    #{tree+1}*16    ;Is it a seed, sapling, or tree?
            BCC    DstryTree       ;Branch if it is
            BRA    DestroyDir      ;Otherwise test for directory destroy

:3          LDA    #fileBusy
DstryErr    SEC                    ;Inform user that file can't
            RTS                    ; be destroyed at this time

DstryTree   EQU    *               ;Destroy a tree file
            STA    storType        ;Save storage type
            LDX    #$05
            LDA    #$00            ;Set "DeTree" input variables
:loop       STA    storType,X      ;Variables must be
            DEX                    ; in order:deBlock, dTree, dSap, dSeed
            BNE    :loop           ;Loop until all set to zero
            LDA    #$02
            STA    dSeed+1         ;This avoids an extra file i/o

********************** see rev note #73 **********************
********************* see rev note #49 **********************
********************** see rev note #41 *********************
            
            INC    delFlag         ;Don't allow DeTree to zero index blocks
            JSR    DeTree          ;Make trees and saplings into seeds
            DEC    delFlag         ;Reset flag
            BCS    DstryErr1       ;(de-evolution)

DstryLast   LDX    firstBlkH
            LDA    firstBlkL       ;Now deallocate seed
            JSR    Dealloc
            BCS    DstryErr1
            JSR    UpdateBitMap

DstryErr1   PHA                    ;Save error code (if any)
            LDA    #$00            ;Update directory to free entry space
            STA    d_file+d_stor
            CMP    h_fileCnt       ;File entry wrap?
            BNE    :2              ;Branch if no carry adjustment
            DEC    h_fileCnt+1     ;Take carry from high byte of file entries
:2          DEC    h_fileCnt       ;Mark header with one less file
            JSR    DvcbRev         ;Go update block count in VCB
            JSR    ReviseDir       ;Update directory last...
            TAX
            PLA
            BCC    :3
            TXA
:3          CMP    #badSystemCall
            RTS

*-------------------------------------------------
* Update free block count in VCB

DvcbRev     LDY    vcbPtr
            LDA    deBlock         ;Add blks freed to
            ADC    vcb+vcbFreeBlks,Y; total free blks
            STA    vcb+vcbFreeBlks,Y;Update current free block count
            LDA    deBlock+1
            ADC    vcb+vcbFreeBlks+1,Y
            STA    vcb+vcbFreeBlks+1,Y
            LDA    #$00            ;Force rescan for free blks
            STA    vcb+vcbCurrBitMap,Y;  from first bitmap
            RTS

ToDstLast   BCC    DstryLast       ;Always

DestroyDir  CMP    #directoryFile*16;Is this a directory file?
            BNE    DirCompErr      ;No, report file incompatible
            JSR    FindBitMap      ;Make sure a buffer is available for the bitmap
            BCS    DstryDirErr

            LDA    d_file+d_first  ;Read in first block
            STA    blockNum        ; of directory into genBuf
            LDA    d_file+d_first+1
            STA    blockNum+1
            JSR    RdGBuf
            BCS    DstryDirErr

            LDA    genBuf+4+hFileCnt;Find out if any files exist on this directory
            BNE    DstryDirAccs    ;Branch if any exist
            LDA    genBuf+4+hFileCnt+1
            BEQ    DstryDir1
DstryDirAccs       LDA             #invalidAccess
            JSR    SysErr

DstryDir1   STA    genBuf+4        ;Make it an invalid subdir
            JSR    WrtGBuf
            BCS    DstryDirErr
:loop       LDA    genBuf+2        ;Get forward link
            CMP    #$01            ;Test for no link
            LDX    genBuf+3
            BNE    :1
            BCC    ToDstLast       ;If no link, then finished

:1          JSR    Dealloc         ;Free this block
            BCS    DstryDirErr
            LDA    genBuf+2
            LDX    genBuf+3
            JSR    RdBlkAX
            BCC    :loop           ;Loop until all are freed
DstryDirErr RTS

DirCompErr  LDA    #badFileFormat  ;File is not compatible
            JSR    SysErr

* Mark as FCB as dirty so the directory will be flushed on 'flush'

FCBUsed     PHA                    ;Save regs
            TYA
            PHA
            LDY    fcbPtr
            LDA    fcb+fcbDirty,Y  ;Fetch current fcbDirty byte
            ORA    #fcbMod         ;Mark FCB as dirty
            STA    fcb+fcbDirty,Y  ;Save it back
            PLA
            TAY                    ; & restore regs
            PLA
            RTS