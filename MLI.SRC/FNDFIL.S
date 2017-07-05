**************************************************
* Get File entry

FindFile    JSR    LookFile        ;See if file exists
            BCS    NoFind          ;Branch if an error was encountered
MovEntry    LDY    h_entLen        ;Move entire entry info
:loop       LDA    (dirBufPtr),Y
            STA    d_file+d_stor,Y ; to a safe area
            DEY
            BPL    :loop
            LDA    #$00            ;To indicate all is well
NoFind      RTS                    ;Return condition codes

*-------------------------------------------------
* Follow path to a file

LookFile    JSR    PrepRoot        ;Find volume and set up other boring stuff
            BCS    FndErr          ;Pass back any error encountered
            BNE    LookFile0       ;Branch if more than root
            LDA    #>genBuf        ;Otherwise, report a badpath error
            STA    dirBufPtr+1     ;(but first create a phantom entry for open)
            LDA    #<genBuf+4      ;Skip 4-byte blk link ptrs
            STA    dirBufPtr

            LDY    #d_auxID        ;First move in id, and date stuff
:loop1      LDA    (dirBufPtr),Y
            STA    d_file,Y
            DEY
            CPY    #d_creDate-1
            BNE    :loop1

:loop2      LDA    rootStuff-d_fileID,Y
            STA    d_file,Y
            DEY
            CPY    #d_fileID-1
            BNE    :loop2

            LDA    #directoryFile*16;Fake directory file
            STA    d_file+d_stor
            LDA    genBuf+2        ;A forward link?
            ORA    genBuf+3
            BNE    :1              ;Yes

            LDA    #$02
            STA    d_file+d_eof+1
            LDA    #$01            ;Allocate 1 blk
            STA    d_file+d_usage
:1          LDA    #badPathSyntax
            RTS

* Scan subdir for file

LookFile0   STZ    noFree          ;Reset free entry indicator
            SEC                    ;Indicate that dir to be searched has header in this blk
ScanDirLoop STZ    totEnt          ;reset entry counter
            JSR    LookName        ;Look for name pointed to by pnPtr
            BCC    NameFound       ;Branch if name was found
            LDA    entCnt          ;Have we looked at all of the
            SBC    totEnt          ; entries in this directory?
            BCC    :11             ;Maybe, check hi count
            BNE    LookFile2       ;No, read next directory block
            CMP    entCnt+1        ;Has the last entry been looked at (A=0)
            BEQ    ErrFNF          ;Yes, give 'file not found' error
            BNE    LookFile2       ;Branch always

:11         DEC    entCnt+1        ;Should be at least 1
            BPL    LookFile2       ;(this should be branch always...)
ErrDir      LDA    #dirError       ;Report directory messed up
FndErr      SEC
            RTS

LookFile2   STA    entCnt          ;Keep running count
            LDA    #>genBuf        ;Reset indirect pointer
            STA    dirBufPtr+1
            LDA    genBuf+2        ;Get link to next directory block
            BNE    NxtDir0         ;(if there is one)
            CMP    genBuf+3        ;Are both zero, i.e. no link?
            BEQ    ErrDir          ;If so, then not all entries were accounted for
NxtDir0     LDX    genBuf+3        ;A has value for block # (low)
            JSR    RdBlkAX         ;Go read the next linked directory in
            BCC    ScanDirLoop     ;Branch if no error
            RTS                    ;Return error (in A)

* No more file entries

ErrFNF      LDA    noFree          ;Was any free entry found?
            BNE    FNF0

            LDA    genBuf+2        ;Test link
            BNE    TellFree
            CMP    genBuf+3        ;If both are zero, then give up
            BEQ    FNF0            ; simply report 'not found'

TellFree    STA    d_entBlk
            LDA    genBuf+3
            STA    d_entBlk+1      ;Assume first entry of next block
            LDA    #$01            ; is free for use
            STA    d_entNum
            STA    noFree          ;Mark d_entNum as valid (for create)
FNF0        JSR    NxtPNameZ       ;Test for 'file not found' versus 'path not found'

ErrPath1    SEC                    ;If non-zero then 'path not found'
            BEQ    :21
            LDA    #pathNotFound   ;Report no such path
            RTS

:21         LDA    #fileNotFound   ;Report file not found
            RTS

* File entry found

NameFound   JSR    NxtPName        ;Adjust index to next name in path
            BEQ    FileFound       ;Branch if that was last name
            LDY    #d_stor         ;Be sure this is a directory entry
            LDA    (dirBufPtr),Y   ;High nibble will tell
            AND    #$F0
            CMP    #directoryFile*16;Is it a sub-directory?
            BNE    ErrPath1        ;Report the user's mistake

            LDY    #d_first        ;Get address of first sub-directory block
            LDA    (dirBufPtr),Y
            STA    blockNum        ;(no checking is done here for a valid
            INY                    ; block number... )
            STA    d_head          ;Save as file's header block too
            LDA    (dirBufPtr),Y
            STA    blockNum+1
            STA    d_head+1
            JSR    RdGBuf          ;Read sub-directory into gbuf
            BCS    FndErr1         ;Return immediately any error encountered

            LDA    genBuf+4+hFileCnt;Get the number of files
            STA    entCnt          ; contained in this directory
            LDA    genBuf+4+hFileCnt+1
            STA    entCnt+1
            LDA    genBuf+4+hPassEnable;Make sure password disabled
            LDX    #$00
            SEC
            ROL
TestPass0   BCC    :1
            INX
:1          ASL
            BNE    TestPass0
            CPX    #$05            ;Is password disabled?
            BEQ    MovHead
            LDA    #badFileFormat  ;Tell them this directory is not compatible
FndErr1     SEC
            RTS

MovHead     JSR    MoveHeadZ       ;Move info about this directory
            JMP    LookFile0       ;Do next local pathname

*-------------------------------------------------
* Copy directory (vol/sub) header

MoveHeadZ   LDX    #$0A            ;move info about this directory
:loop1      LDA    genBuf+4+hCreDate,X
            STA    h_creDate,X
            DEX
            BPL    :loop1

            LDA    genBuf+4        ;If this is root, then nothing to do
            AND    #$F0
            EOR    #$F0            ;Test header type
            BEQ    :11             ;Branch if root

            LDX    #$03            ;Otherwise, save owner info about this header
:loop2      LDA    genBuf+4+hOwnerBlk,X
            STA    ownersBlock,X
            DEX
            BPL    :loop2
:11         RTS

*-------------------------------------------------
* Save dir entry # & block

FileFound   EQU    *
EntAdr      LDA    h_maxEnt        ;Figure out which is entry number this is
            SEC
            SBC    cntEnt          ;max entries - count entries + 1 = entry number
            ADC    #$00            ;(carry is/was set)
            STA    d_entNum

            LDA    blockNum
            STA    d_entBlk
            LDA    blockNum+1      ; & indicate blk # of this dir
            STA    d_entBlk+1
            CLC
            RTS

*-------------------------------------------------
* Search one dir block for file

LookName    LDA    h_maxEnt        ;reset count of files per block
            STA    cntEnt
            LDA    #>genBuf
            STA    dirBufPtr+1
            LDA    #$04
LookName1   STA    dirBufPtr       ;Reset indirect pointer to genBuf
            BCS    LookName2       ;Branch if this block contains a header
            LDY    #$00
            LDA    (dirBufPtr),Y   ;Get length of name in dir
            BNE    IsName          ;Branch if there is a name

            LDA    noFree          ;Test to see if a free entry has been declared
            BNE    LookName2       ;Yes bump to next entry
            JSR    EntAdr          ;Set address for current entry
            INC    noFree          ;Indicate a free spot has been found
            BNE    LookName2       ;Branch always

IsName      AND    #$0F            ;Strip type (this is checked by 'FileFound')
            INC    totEnt          ;(bump count of valid files found)
            STA    namCnt          ;Save name length as counter
            LDX    pnPtr           ;Get index to current path
            CMP    pathBuf,X       ;Are both names of the same length?
            BNE    LookName2       ;No, bump to next entry

CmpNames    INX                    ;(first) next letter index
            INY
            LDA    (dirBufPtr),Y   ;Compare names letter by letter
            CMP    pathBuf,X
            BNE    LookName2
            DEC    namCnt          ;Have all letters been compared?
            BNE    CmpNames        ;No, continue..
            CLC                    ;By golly, we got us a match!
NoName      RTS

LookName2   DEC    cntEnt          ;Have we checked all possible entries in this blk?
            SEC
            BEQ    NoName          ;Yes, give up

            LDA    h_entLen        ;Add entry length to current pointer
            CLC
            ADC    dirBufPtr
            BCC    LookName1       ;Branch if we're still in the first page
            INC    dirBufPtr+1     ;Look on second page
            CLC                    ;Carry should always be clear before looking at next
            BCC    LookName1       ;Branch always...