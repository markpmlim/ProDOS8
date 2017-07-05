**************************************************
* CREATE call

Create      JSR    LookFile        ;Check for duplicate / get free entry
            BCS    TestFnF         ;Error code in A-reg may be 'file not found'
            LDA    #dupPathname    ;Tell 'em a file of that name already exists
CrErr1      SEC                    ;Indicate error encountered
            RTS                    ;Return error in A-reg

TestFnF     CMP    #fileNotFound   ;'file not found' is what we want
            BNE    CrErr1          ;Pass back other error
            LDY    #c_fileKind     ;Test for "tree" or directory file
            LDA    (parm),Y        ;No other kinds are legal
            CMP    #tree+1         ;Is it seed, sapling, or tree?
            BCC    :1               ;Branch if it is
            CMP    #directoryFile
            BNE    CrTypErr        ;Report type error if not directory.

:1          LDA    DevNum          ;Before proceeding, make sure destination
            JSR    TestWrProtZ     ; device is not write protected...
            BCS    CrRtn
            LDA    noFree          ;Is there space in directory to add this file?
            BEQ    XtnDir          ;Branch if not
            JMP    CreateZ         ;Otherwise, go create file

CrTypErr    LDA    #badStoreType
            SEC                    ;Indicate error
CrRtn       RTS

XtnDir      LDA    ownersBlock     ;Before extending directory,
            ORA    ownersBlock+1   ; make sure it is a sub-directory!!!
            BNE    :11
            LDA    #volDirFull     ;Otherwise report directory full error.
            SEC
            RTS

:11         LDA    blockNum        ;Preserve disk addr of current (last)
            PHA
            LDA    blockNum+1      ; directory link, before allocating
            PHA                    ; an extend block
            JSR    Alloc1Blk       ;Allocate a block for extending directory
            PLX
            STX    blockNum+1      ;Restore block addr of directory stuff in gbuf
            PLX
            STX    blockNum
            BCS    CrRtn           ;Branch if unable to allocate
            STA    genBuf+2        ;Save low block address in current directory
            STY    genBuf+3        ; & hi addr too
            JSR    WrtGBuf         ;Go update dir. block with new link
            BCS    CrRtn           ;(report any errors.)

            LDX    #$01
SwapBloks   LDA    blockNum,X      ;Now prepare new directory block
            STA    genBuf,X        ;Use current block as back link
            LDA    genBuf+2,X
            STA    blockNum,X      ; & save new block as next to be written
            DEX
            BPL    SwapBloks

            INX                    ;Now X=0
            TXA                    ; and A=0 too
ClrDir      STA    genBuf+2,X
            STA    genBuf+$100,X
            INX
            BNE    ClrDir

            JSR    WrtGBuf         ;Write prepared directory extension
            BCS    CrRtn           ;Report errors

            LDA    ownersBlock
            LDX    ownersBlock+1
            JSR    RdBlkAX         ;Read in 'parent' directory block
            LDX    ownersEnt       ;Prepare to calculate entry address
            LDA    #genBuf/256
            STA    dirBufPtr+1

            LDA    #$04            ;Skip 4-byte blk link ptrs
OCalc       CLC
            DEX                    ;Has entry addr been computed?
            BEQ    :21             ;Branch if yes
            ADC    ownersLen       ;Bump to next entry adr
            BCC    OCalc
            INC    dirBufPtr+1     ;Entry must be in second 256 of block
            BCS    OCalc           ;Branch always

:21         STA    dirBufPtr
            LDY    #d_usage        ;Index to block count
:loop       LDA    (dirBufPtr),Y
            ADC    dIncTbl-d_usage,Y;Add 1 to block count and 
            STA    (dirBufPtr),Y
            INY
            TYA                    ; $200 to the directory's end of file
            EOR    #d_eof+3        ;Done with usage/eof update?
            BNE    :loop           ;Branch if not

            JSR    WrtGBuf         ;Go update parent
            BCS    :2
            JMP    Create
:2          RTS

CreateZ     EQU    *               ;Build new file

*-------------------------------------------------
* Zero general purpose buffer ($DC00-$DDFF)

ZeroGBuf    LDX    #$00
ClrGBuf     STZ    genBuf,X        ;Zero out genBuf
            STZ    genBuf+$100,X
            INX
            BNE    ClrGBuf         ;loop until zipped!

            LDY    #c_time+1       ;Move user specified date/time
:loop1      LDA    (parm),Y        ; to directory entry
            STA    d_file+d_creDate-c_date,y
            TXA                    ;If all four bytes of date/time are zero
            ORA    (parm),Y        ; then use built in date/time
            TAX
            DEY                    ;Have all four bytes been moved and tested?
            CPY    #c_fileKind
            BNE    :loop1          ;Branch if not
            TXA                    ;Does user want default time?
            BNE    :1              ;Branch if not

            LDX    #$03
:loop2      LDA    DateLo,X        ;Move current default date/time
            STA    d_file+d_creDate,X
            DEX
            BPL    :loop2

:1          LDA    (parm),Y        ;(y is indexing fileKind)
            CMP    #tree+1
            LDA    #seedling*16    ;Assume tree type
            BCC    :2
            LDA    #directoryFile*16;Its dir since file kind has already been verified
:2          LDX    namPtr          ;Get index to 'local' name of pathname
            ORA    pathBuf,X       ;Combine file kind with name length
            STA    d_file+d_stor   ;(sos calls this 'storage type')
            AND    #$0F            ;Strip back to name length
            TAY                    ; & use as count-down for move
            CLC
            ADC    namPtr          ;Calculate end of name
            TAX

CrName      LDA    pathBuf,X       ;Now move local name as filename
            STA    d_file+d_stor,Y
            DEX
            DEY                    ;All characters transfered?
            BNE    CrName          ;Branch if not

            LDY    #c_attr         ;Index to 'access' parameter
            LDA    (parm),Y
            STA    d_file+d_attr
            INY                    ;Also move 'file identification'
            LDA    (parm),Y
            STA    d_file+d_fileID

:loop1      INY                    ; & finally, the auxillary
            LDA    (parm),Y        ; identifcation bytes
            STA    d_file+d_auxID-c_auxID,Y
            CPY    #c_auxID+1
            BNE    :loop1

            LDA    XDOSver         ;Save current xdos version number
            STA    d_file+d_sosVer
            LDA    compat          ; & backward compatiblity number
            STA    d_file+d_comp

            LDA    #$01            ;Usage is always 1 block
            STA    d_file+d_usage
            LDA    d_head          ;Place back pointer to header block
            STA    d_file+d_dHdr
            LDA    d_head+1
            STA    d_file+d_dHdr+1

            LDA    d_file+d_stor   ;Get storage type again
            AND    #$E0            ;Is it a directory?
            BEQ    CrAlocBlk       ;Branch if seed file

            LDX    #30             ;Move header to data block
:loop2      LDA    d_file+d_stor,X
            STA    genBuf+4,X
            DEX
            BPL    :loop2

            EOR    #$30            ;($Dn->$En) last byte is fileKind/namlen
            STA    genBuf+4        ;Make it a directory header mark

            LDX    #$07            ;Now overwrite password area
:loop3      LDA    Pass,X          ; and other header info
            STA    genBuf+4+hPassEnable,X
            LDA    XDOSver,X
            STA    genBuf+4+hVer,X
            DEX
            BPL    :loop3

            LDX    #$02            ; & include info about 'parent directory
            STX    d_file+d_eof+1
:loop4      LDA    d_entBlk,X
            STA    genBuf+4+hOwnerBlk,X
            DEX
            BPL    :loop4

            LDA    h_entLen        ;Lastly the length of parent's dir entries
            STA    genBuf+4+hOwnerLen

CrAlocBlk   JSR    Alloc1Blk       ;Get address of file's data block
            BCS    CrErr3          ;Branch if error encountered
            STA    d_file+d_first
            STY    d_file+d_first+1
            STA    blockNum
            STY    blockNum+1
            JSR    WrtGBuf         ;Go write data block of file
            BCS    CrErr3
            INC    h_fileCnt       ;Add 1 to total # of files in this directory
            BNE    :1
            INC    h_fileCnt+1
:1          JSR    ReviseDir       ;Go revise directories with new file
            BCS    CrErr3
            JMP    UpdateBitMap    ;Lastly, update volume bitmap

*-------------------------------------------------
* Point dirBufPtr ($48/$49) at directory entry

EntCalc     LDA    #genBuf/256     ;Set high address of directory
            STA    dirBufPtr+1     ; entry index pointer
            LDA    #$04            ;Calculate address of entry based
            LDX    d_entNum        ; on the entry number
:loop1      CLC
:loop2      DEX                    ;addr=genBuf+((entnum-1)*entlen)
            BEQ    :exitLoop
            ADC    h_entLen
            BCC    :loop2
            INC    dirBufPtr+1     ;Bump hi address
            BCS    :loop1          ;Branch always
:exitLoop   STA    dirBufPtr       ;Save newly calculated low address
CrErr3      EQU    *
DError2     RTS                    ;Return errors

*-------------------------------------------------
* Update directory(s)

ReviseDir   LDA    DateLo          ;If no clock,
            BEQ    ReviseDirZ      ; then don't touch mod time/date

            LDX    #$03
:loop       LDA    DateLo,X        ;Move last modification date/time
            STA    d_file+d_modDate,X; to entry being updated
            DEX
            BPL    :loop

ReviseDirZ  LDA    d_file+d_attr   ;Mark entry as backupable
            ORA    bkBitFlg        ; bit 5 = backup needed bit
            STA    d_file+d_attr
            LDA    d_dev           ;Get device number of directory
            STA    DevNum          ; to be revised
            LDA    d_entBlk        ; & address of directory block
            LDX    d_entBlk+1
            JSR    RdBlkAX         ;Read block into general purpose buffer
            BCS    DError2

            JSR    EntCalc         ;Fix up pointer to entry location within gbuf
            LDY    h_entLen        ;Now move 'd_' stuff to directory
            DEY
:loop1      LDA    d_file+d_stor,Y
            STA    (dirBufPtr),Y
            DEY
            BPL    :loop1

            LDA    d_head          ;Is the entry block the same as the
            CMP    blockNum        ; entry's header block?
            BNE    SavEntDir       ;No, save entry block
            LDA    d_head+1        ;Maybe, test high addresses
            CMP    blockNum+1
            BEQ    UpHead          ;Branch if they are the same block

SavEntDir   JSR    WrtGBuf         ;Write updated directory block
            BCS    DError2         ;Return any error
            LDA    d_head          ;Get address of header block
            LDX    d_head+1
            JSR    RdBlkAX         ;Read in header block for modification
            BCS    DError2

UpHead      LDY    #$01            ;Update current # of files in this directory
:loop2      LDA    h_fileCnt,Y
            STA    genBuf+hFileCnt+4,Y;(current entry count)
            DEY
            BPL    :loop2

            LDA    h_attr          ;Also update header's attributes
            STA    genBuf+hAttr+4
            JSR    WrtGBuf         ;Go write updated header
            BCS    DError1

Ripple      LDA    genBuf+4        ;Test for 'root' directory
            AND    #$F0            ;If it is root, then dir revision is complete
            EOR    #$F0            ;(leaves carry clear)
            BEQ    DirRevDone      ;Branch if ripple done

            LDA    genBuf+hOwnerEnt+4;Get entry number &
            STA    d_entNum
            LDA    genBuf+hOwnerEnt+5; the length of entries in that dir
            STA    h_entLen

            LDA    genBuf+hOwnerBlk+4;Get addr of parent entry's dir block
            LDX    genBuf+hOwnerBlk+5
            JSR    RdBlkAX         ;Read that sucker in
            BCS    DError1

            JSR    EntCalc         ;Get indirect ptr to parent entry in genBuf
            LDA    DateLo          ;Don't touch mod
            BEQ    RUpdate         ; if no clock...

            LDX    #$03            ;Now update the modification date
            LDY    #d_modDate+3    ; & time for this entry too
RipTime     LDA    DateLo,X
            STA    (dirBufPtr),Y
            DEY
            DEX
            BPL    RipTime         ;Move all for bytes...
            
* Write updated entry back to disk. (Assumes blockNum undisturbed)

RUpdate     JSR    WrtGBuf
            BCS    DError1         ;Give up on any error

            LDY    #d_dHdr         ;Now compare current block number to
            LDA    (dirBufPtr),Y   ; this entry's header block
            INY
            CMP    blockNum        ;Are low addresses the same? 
            STA    blockNum        ;(save it in case it's not)
            BNE    :1              ;Branch if entry does not reside in same block as header
            LDA    (dirBufPtr),Y   ;Check high address just to be sure
            CMP    blockNum+1
            BEQ    Ripple          ;They are the same, continue ripple to root directory

:1          LDA    (dirBufPtr),Y   ;They aren't the same,
            STA    blockNum+1      ; read in this directory's header
            JSR    RdGBuf
            BCC    Ripple          ;Continue if read was good
DError1     RTS

TestErr     LDA    #unknownVol     ;Not tree or dir - not a recognized type!
            SEC
            RTS

*-------------------------------------------------
* Is this a ProDOS vol?

TestSOS     LDA    genBuf          ;Test SOS stamp
            ORA    genBuf+1
            BNE    TestErr
            LDA    genBuf+4        ;Test for header
            AND    #$E0
            CMP    #$E0
            BNE    TestErr         ;Branch if not SOS header (no error number)
DirRevDone  CLC                    ;Indicate no error
            RTS
