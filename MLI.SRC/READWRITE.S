**************************************************
* READ Call

Read        JSR    MovDBuf         ;First transfer buffer adr & request count to a
            JSR    MovCBytes       ; more accessible location, also get fcbAttr, CLC
            PHA                    ;Save attributes for now
            JSR    CalcMark        ;Calc mark after read, test mark>eof
            PLA                    ;Carry Set indicates end mark>eof
            AND    #readEnable     ;Test for read enabled first
            BNE    :1              ;Branch if ok to read
            LDA    #invalidAccess  ;Report illegal access
            BNE    GoFix1          ;Branch always taken

:1          BCC    Read2           ;Branch if result mark<eof
                                   ; Adjust request to read up to (but not including) end of file. 
            LDY    fcbPtr
            LDA    fcb+fcbEOF,Y    ;Result= (eof-1)-position
            SBC    tPosll
            STA    cBytes
            STA    rwReqL
            LDA    fcb+fcbEOF+1,Y
            SBC    tPoslh
            STA    cBytes+1
            STA    rwReqH
            ORA    cBytes          ;If both bytes are zero, report EOF error
            BNE    NotEOF
            LDA    #eofEncountered
GoFix1      JMP    ErrFixZ

Read2       LDA    cBytes
            ORA    cBytes+1
            BNE    NotEOF          ;Branch if read request definitely non-zero
GoRdDone    JMP    RWDone          ;Do nothing

NotEOF      JSR    ValDBuf         ;Validate user's data buffer range
            BCS    GoFix1          ;Branch if memory conflict
            JSR    GfcbStorTyp     ;Get storage type
            CMP    #tree+1         ;Now find if it's a tree or other
            BCC    TreeRead        ;Branch if a tree file
            JMP    DirRead         ;Othewise assume it's a directory

TreeRead    JSR    RdPosn          ;Get data pointer set up
            BCS    GoFix1          ;Report any errors
            JSR    PrepRW          ;Test for newline, sets up for partial read
            JSR    ReadPart        ;Move current data buffer contents to user area
            BVS    GoRdDone        ;Branch if request is satisfied
            BCS    TreeRead        ;Carry set indicates newline is set

            LDA    rwReqH          ;Find out how many blocks are to be read
            LSR                    ;If less than two,
            BEQ    TreeRead        ; then do it the slow way

            STA    bulkCnt         ;Save bulk block count
            JSR    GetFCBStat      ;Make sure current data area doesn't need writing before
            AND    #dataMod        ; resetting pointer to read directly into user's area.
            BNE    TreeRead        ;Branch if data need to be written

* Setup for fast Direct Read rtn

            STA    ioAccess        ; to force first call thru all device handler checking
            LDA    userBuf         ;Make the data buffer the user's space
            STA    dataPtr
            LDA    userBuf+1
            STA    dataPtr+1

RdFast      JSR    RdPosn          ;Get next block directly into user space
            BCS    ErrFix          ;Branch on any error
RdFastLoop  INC    dataPtr+1
            INC    dataPtr+1       ;Bump all pointers by 512 (one block)
            DEC    rwReqH
            DEC    rwReqH
            INC    tPoslh
            INC    tPoslh
            BNE    :11             ;Branch if position does not get to a 64K boundary
            INC    tPosHi          ;Otherwise, must check for a 128K boundary
            LDA    tPosHi          ;If mod 128K has been
            EOR    #$01
            LSR                    ; reached, set Carry
:11         DEC    bulkCnt         ;Have we read all we can fast?
            BNE    :12             ;Branch if more to read

            JSR    FixDataPtr      ;Go fix up data pointer to xdos buffer
            LDA    rwReqL          ;Test for end of read
            ORA    rwReqH          ;Are both zero?
            BEQ    RWDone
            BNE    TreeRead        ;No

:12         BCS    RdFast
            LDA    tPosHi          ;Get index to next block address
            LSR
            LDA    tPoslh
            ROR
            TAY                    ;Index to address is int(pos/512)
            LDA    (tIndex),Y      ;Get low address
            STA    blockNum
            INC    tIndex+1
            CMP    (tIndex),Y      ;Are both hi and low addresses the same?
            BNE    RealRd          ;No, it's a real block address
            CMP    #$00            ;Are both bytes zero?
            BNE    RealRd          ;Nope -- must be real data
            STA    ioAccess        ;Don't do repeatio just after sparse
            BEQ    NoStuff         ;Branch always (carry set)

RealRd      LDA    (tIndex),Y      ;Get high address byte
            CLC
NoStuff     DEC    tIndex+1
            BCS    RdFast          ;Branch if no block to read
            STA    blockNum+1
            LDA    ioAccess        ;Has first call gone to device yet?
            BEQ    RdFast          ;Nope, go thru normal route...
            CLC
            PHP                    ;Interupts cannot occur while calling dmgr
            SEI
            LDA    dataPtr+1       ;Reset hi buffer address for device handler
            STA    bufPtr+1
            JSR    DMgr
            BCS    :31             ;Branch if error
            PLP
            BCC    RdFastLoop      ;No errors, branch always

:31         PLP                    ;Restore interupts
ErrFix      PHA                    ;Save error code
            JSR    FixDataPtr      ;Go restore data pointers, etc...
            PLA
ErrFixZ     PHA                    ;Save error code
            JSR    RWDone          ;Pass back number of bytes actually read
            PLA
            SEC                    ;Report error
            RTS

*-------------------------------------------------
* I/O finish up

RWDone      LDY    #c_xferCnt      ;Return total # of bytes actually read
            SEC                    ;This is derived from cbytes-rwreq
            LDA    cBytes
            SBC    rwReqL
            STA    (parm),Y
            INY
            LDA    cBytes+1
            SBC    rwReqH
            STA    (parm),Y
            JMP    RdPosn          ;Leave with valid position in FCB

*-------------------------------------------------
* Set up buffer indexing
* Exit
*  C=1 newline enabled
*  (Y) = index to first data byte to be xferred
*  (X) = LOB of request count

PrepRW      LDY    fcbPtr          ;Adjust pointer to user's buffer
            SEC                    ; to make the transfer
            LDA    userBuf
            SBC    tPosll
            STA    userBuf
            BCS    :1              ;Branch if no adjustment to hi addr needed
            DEC    userBuf+1
:1          LDA    fcb+fcbNLMask,Y ;Test for new line enabled
            CLC
            BEQ    NoNewLine       ;Branch if newline is not enabled

            SEC                    ;Carry set indicates newline enabled
            STA    nlMask
            LDA    fcb+fcbNewLin,Y ;Move newline character
            STA    nlChar          ; to more accessible spot

NoNewLine   LDY    tPosll          ;Get index to first data byte
            LDA    dataPtr         ;Reset low order of posPtr to beginning of page
            STA    posPtr
            LDX    rwReqL          ; & lastly get low order count of requested bytes
            RTS                    ;Return statuses...

*-------------------------------------------------
* Copy from I/O blk buffer to data buffer
* Exit if : 1. len goes to zero
*           2. next block is needed
*           3. newLine char is found
* Exit
*  V = 1 - done
*  V = 0 - next blk needed

ReadPart    TXA                    ;(X)=low count of bytes to move
            BNE    :1              ;Branch if request is not an even page
            LDA    rwReqH          ;A call of zero bytes should never get here!
            BEQ    SetRdDone       ;Branch if nothin' to do
            DEC    rwReqH
:1          DEX

* NB. In order for the same Y-reg to be used below,
* the ptr to user's buffer had been adjusted (see
* code in PrepRW rtn)

RdPart      LDA    (posPtr),Y      ;Move data to user's buffer
            STA    (userBuf),Y     ; one byte at a time
            BCS    TestNewLine     ;Let's test for newline first!
RdPart2     TXA                    ;Note: (X) must be unchanged from TestNewLine!
            BEQ    EndReqChk       ;See if read request is satisfied...
RdPart1     DEX                    ;Decr # of bytes left to move
            INY                    ;Page crossed?
            BNE    RdPart          ;No, move next byte
            LDA    posPtr+1        ;Test for end of buffer
            INC    userBuf+1       ; but first adjust user buffer
            INC    tPoslh          ; pointer and position
            BNE    :11
            INC    tPosHi
:11         INC    posPtr+1        ;& sos buffer high address
            EOR    dataPtr+1       ;(Carry has been cleverly undisturbed.)
            BEQ    RdPart          ;Branch if more to read in buffer
            CLV                    ;Indicate not finished
            BVC    RdPartDone      ;Branch always

EndReqChk   LDA    rwReqH          ;NB. (X)=0
            BEQ    RdReqDone       ;Branch if request satisfied
            INY                    ;Done with this block of data?
            BNE    :31             ;No, adjust high byte of request

            LDA    posPtr+1        ;Maybe-check for end of block buffer
            EOR    dataPtr+1       ;(don't disturb carry)
            BNE    :32             ;Branch if hi count can be dealt with next time
:31         DEC    rwReqH          ;Decr count by 1 page
:32         DEY                    ;Restore proper value to Y-reg
            BRA    RdPart1

TestNewLine LDA    (posPtr),Y      ;Get last byte transfered again
            AND    nlMask          ;Only bits on in mask are significant
            EOR    nlChar          ;Have we matched newline character?
            BNE    RdPart2         ;No, read next

RdReqDone   INY                    ;Adjust position
            BNE    SetRdDone
            INC    userBuf+1       ;Bump pointers
            INC    tPoslh
            BNE    SetRdDone
            INC    tPosHi
SetRdDone   BIT    SetVFlag        ;(set V flag)

RdPartDone  STY    tPosll          ;Save low position
            BVS    :41
            INX                    ;Leave request as +1 for next call 
:41         STX    rwReqL          ; & remainder of request count.
            PHP                    ;Save statuses
            CLC                    ;Adjust user's low buffer address
            TYA
            ADC    userBuf
            STA    userBuf
            BCC    :42
            INC    userBuf+1       ;Adjust hi address as needed
:42         PLP                    ;Restore return statuses
SetVFlag    RTS                    ;(this byte <$60> is used to set V flag)

*-------------------------------------------------
* Cleanup after direct I/O

FixDataPtr  LDA    dataPtr         ;Put current user buffer
            STA    userBuf         ; address back to normal
            LDA    dataPtr+1
            STA    userBuf+1       ;Bank pair byte should be moved also
            LDY    fcbPtr          ;Restore buffer address
            JMP    FndFCBuf

*-------------------------------------------------
* Read directory file...

DirRead     JSR    RdPosn
            BCS    ErrDirRd        ;Pass back any errors
            JSR    PrepRW          ;Prepare for transfer
            JSR    ReadPart        ;Move data to user's buffer
            BVC    DirRead         ;Repeat until request is satisfied
            JSR    RWDone          ;Update FCB as to new position
            BCC    :1              ;Branch if all is well
            CMP    #eofEncountered ;Was last read to end of file?
            SEC                    ;Anticipate some other problem
            BNE    :Ret            ;Branch if not EOF error

            JSR    SavMark
            JSR    ZipData         ;Clear out data block
            LDY    #$00            ;Provide dummy back pointer for future re-position
            LDX    fcbPtr          ;Get hi byte of last block
:loop       LDA    fcb+fcbDataBlk,X
            STA    (dataPtr),Y
            LDA    #$00            ;Mark current block as imposible
            STA    fcb+fcbDataBlk,X
            INX
            INY                    ;Bump indexes to do both hi & low bytes
            CPY    #$02
            BNE    :loop
:1          CLC                    ;Indicate no error
:Ret        RTS

ErrDirRd    JMP    ErrFixZ

*-------------------------------------------------
* Copy caller's I/O len
* Exit
*  (A)=attributes
*  (Y)=(fcbptr)

MovCBytes   LDY    #c_reqCnt       ;Move request count
            LDA    (parm),Y        ; to a more accessible location
            STA    cBytes
            STA    rwReqL
            INY
            LDA    (parm),Y
            STA    cBytes+1
            STA    rwReqH
            LDY    fcbPtr          ;Also return (Y)=val(fcbptr)
            LDA    fcb+fcbAttr,Y   ; & (A)=attributes
            CLC                    ; & carry clear...
            RTS

*-------------------------------------------------
* Point userBuf ($4E,$4F) to caller's data buffer
* Exit
*  (A) = file's storage type

MovDBuf     LDY    #c_dataBuf      ;Move pointer to user's buffer to bfm
            LDA    (parm),Y
            STA    userBuf
            INY
            LDA    (parm),Y
            STA    userBuf+1

GfcbStorTyp LDY    fcbPtr          ;Also return storage type
            LDA    fcb+fcbStorTyp,Y;(on fall thru)
            RTS

*-------------------------------------------------
*  Copy file mark, compute and compare end mark

CalcMark    LDX    #$00            ;This subroutine adds the requested byte
            LDY    fcbPtr
            CLC
:loop       LDA    fcb+fcbMark,Y   ;Count to mark, and returns sum
            STA    tPosll,X        ; in scrtch and also returns mark in tPos
            STA    oldMark,X       ; and oldMark
            ADC    cBytes,X
            STA    scrtch,X        ;On exit: Y, X, A=unknown 
            TXA                    ;Carry set indicates scrtch>eof
            EOR    #$02            ;(cBytes+2 always = 0)
            BEQ    EOFtest
            INY
            INX
            BNE    :loop           ;Branch always

EOFtest     LDA    scrtch,X        ;New mark in scrtch!
            CMP    fcb+fcbEOF,Y    ;Is new position > eof?
            BCC    :Ret            ;No, proceed
            BNE    :Ret            ;Yes, adjust 'cBytes' request
            DEY
            DEX                    ;Have we compared all three bytes?
            BPL    EOFtest
:Ret        RTS

*-------------------------------------------------
*  Set new mark & eof

WrErrEOF    JSR    Plus2FCB        ;Reset EOF to pre-error position
:loop       LDA    oldEOF,X        ;Place oldEOF back into fcb
            STA    fcb+fcbEOF,Y
            LDA    oldMark,X       ;Also reset mark to last best write position
            STA    fcb+fcbMark,Y
            STA    scrtch,X        ; & copy mark to scrtch for
            DEY                    ; test of EOF less than mark
            DEX
            BPL    :loop
            JSR    Plus2FCB        ;Get pointers to test EOF<mark
            JSR    EOFtest         ;Carry set means mark>EOF!!

* Drop into WrAdjEOF to adjust EOF to mark if necessary.

WrAdjEOF    JSR    Plus2FCB        ;Get (Y)=fcbPtr+2, (X)=2,(A)=(Y)
:loop1      LDA    fcb+fcbEOF,Y    ;Copy EOF to oldEOF
            STA    oldEOF,X
            BCC    :1              ; & if carry set...
            LDA    scrtch,X        ; copy scrtch to fcb's EOF
            STA    fcb+fcbEOF,Y
:1          DEY
            DEX                    ;Copy all three bytes
            BPL    :loop1
            RTS

*-------------------------------------------------
* Set 3-byte indices
* Exit
*  (A)=(Y)=(fcbPtr)+2
*  (X)=2

Plus2FCB    LDA    #$02
            TAX
            ORA    fcbPtr
            TAY
            RTS

**************************************************
* WRITE Call

Write       EQU    *               ;First determine if requested
            JSR    MovCBytes       ; write is legal
            PHA                    ;Save attributes temporarily
            JSR    CalcMark        ;Save a copy of EOF to oldEOF, set/clr Carry
            JSR    WrAdjEOF        ; to determine if new mark > EOF
            PLA                    ;Get attributes again
            AND    #writeEnable
            BNE    Write1          ;It's write enabled

ErrAccess   LDA    #invalidAccess  ;Report illegal access
            BNE    WrtError        ;Always

Write1      JSR    TestWrProt      ;Otherwise, ensure device is not write protected
            BCS    WrtError        ;Report write potected and abort operation
            LDA    cBytes
            ORA    cBytes+1        ;Anything to write?
            BNE    :1              ;branch if write request definitely non-zero
            JMP    RWDone          ;Do nothing

:1          JSR    MovDBuf         ;Move pointer to user's buffer to bfm
            CMP    #tree+1         ; zpage area, also get storage type
            BCS    ErrAccess       ;If not tree, return an access error!

TreeWrite   JSR    RdPosn          ;Read block we're in
            BCS    WrtError
            JSR    GetFCBStat      ;Get file's status
            AND    #dataAloc+idxAloc+topAloc;Need to allocate?
            BEQ    TreeWrt1        ;No

            LDY    #$00            ;Find out if enough disk space is available
:loop       INY                    ; for indexes and data block
            LSR                    ;Count # of blks needed
            BNE    :loop

            STY    reqL            ;Store # of blks needed
            STA    reqH            ;(A)=0
            JSR    TestFreeBlk
            BCS    WrtError        ;Pass back any errors

            JSR    GetFCBStat      ;Now get more specific
            AND    #topAloc        ;Are we lacking a tree top?
            BEQ    TestSapWr       ;No, test for lack of sapling level index
            JSR    MakeTree        ;Go allocate tree top and adjust file type
            BCC    AllocDataBlk    ;Continue with allocation of data block

WrtError    PHA                    ;Save error
            JSR    ErrFixZ
            JSR    WrErrEOF        ;Adjust EOF and mark to pre-error state
            PLA                    ;Restore error code
            SEC                    ;Flag error
            RTS

TestSapWr   JSR    GetFCBStat      ;Get status byte again
            AND    #idxAloc        ;Do we need a sapling level index block?
            BEQ    AllocDataBlk    ;No, assume it's just a data block needed

            JSR    AddNewIdxBlk    ;Go allocate an index block and update tree top
            BCS    WrtError        ;Return any errors

AllocDataBlk       JSR             AllocWrBlk ;Go allocate for data block
            BCS    WrtError

            JSR    GetFCBStat      ;Clear allocation required bits in status
            ORA    #idxMod         ; but first tell 'em index block is dirty
            AND    #$FF-dataAloc-idxAloc-topAloc;Flag these have been allocated
            STA    fcb+fcbStatus,Y
            LDA    tPosHi          ;Calculate position within index block
            LSR
            LDA    tPoslh
            ROR
            TAY                    ;Now put block address into index block
            INC    tIndex+1        ;High byte first
            LDA    scrtch+1
            TAX
            STA    (tIndex),Y
            DEC    tIndex+1        ;(Restore pointer to lower page of index block)
            LDA    scrtch          ;Get low block address
            STA    (tIndex),Y      ;Now store low address

            LDY    fcbPtr          ;Also update file control block to indicate
            STA    fcb+fcbDataBlk,Y; that this block is allocated
            TXA                    ;Get high address again
            STA    fcb+fcbDataBlk+1,Y

TreeWrt1    JSR    PrepRW          ;Write on
            JSR    WrtPart
            BVC    TreeWrite
            JMP    RWDone          ;Update FCB with new position

*-------------------------------------------------
* Copy write data to I/O blk
* Logic is similar to ReadPart rtn
* Exit
*  V = 1 - done
*  V = 0 - More to write

WrtPart     TXA
            BNE    WrtPart1        ;Branch if request is not an even page
            LDA    rwReqH          ;A call of zero bytes should never get here!
            BEQ    SetWrDone       ;Do nothing!

            DEC    rwReqH
WrtPart1    DEX
            LDA    (userBuf),Y     ;Move data from user's buffer
            STA    (posPtr),Y      ; one byte at a time
            TXA
            BEQ    EndWReqChk
WrtPart2    INY                    ;Page crossed?
            BNE    WrtPart1        ;No, move next byte

            LDA    posPtr+1        ;Test for end of buffer
            INC    userBuf+1       ; but first adjust user buffer
            INC    tPoslh          ; pointer and position
            BNE    :1
            INC    tPosHi

* Don't wrap around on file!
            
            BNE    :1
            LDA    #outOfRange     ; Say out of range if >32 meg
            BNE    WrtError        ;Always
:1          INC    posPtr+1        ; and sos buffer high address
            EOR    dataPtr+1       ;(carry has been cleverly undisturbed.)
            BEQ    WrtPart1        ;Crunch if more to write to buffer

            CLV                    ;Indicate not finished
            BVC    WrPartDone      ;Branch always

EndWReqChk  LDA    rwReqH
            BEQ    WrtReqDone      ;Branch if request satisfied
            INY                    ;Are we done with this block of data?
            BNE    :11             ;Branch if not
            LDA    posPtr+1
            EOR    dataPtr+1       ;While this is redundant, it's necessary for
            BNE    :12             ; proper adjustment of request count
:11         DEC    rwReqH          ;(not finished- ok to adjust hi byte.)
:12         DEY                    ;Reset modified Y-reg
            BRA    WrtPart2

WrtReqDone  INY                    ; and position
            BNE    SetWrDone
            INC    userBuf+1       ;bump pointers
            INC    tPoslh
            BNE    SetWrDone
            INC    tPosHi
SetWrDone   BIT    SetVFlag        ;(set V flag)

WrPartDone  STY    tPosll          ;Save low position
            STX    rwReqL          ; and remainder of request count
            PHP                    ;Save statuses
            JSR    GetFCBStat
            ORA    #dataMod+useMod
            STA    fcb+fcbStatus,Y
            CLC                    ;Adjust user's low buffer address
            LDA    tPosll
            ADC    userBuf
            STA    userBuf
            BCC    :21
            INC    userBuf+1       ;Adjust hi address as needed
:21         JSR    FCBUsed         ; Set directory flush bit
            PLP                    ;Restore return statuses
            RTS

*-------------------------------------------------
* Make a tree file by adding a new master index blk

MakeTree    JSR    SwapDown        ;First make curr 1st blk an entry in new top
            BCS    ErrMakeTree     ;Return any errors

            JSR    GfcbStorTyp     ;Find out if storage type has been changed to 'tree'
                                   ;(if not, assume it was originally a seed and
            CMP    #tree           ; both levels need to be built
            BEQ    MakeTree1       ; Otherwise, only an index need be allocated)
            JSR    SwapDown        ;Make previous swap a sap level index block
            BCS    ErrMakeTree

MakeTree1   JSR    AllocWrBlk      ;Get another block address for the sap level index
            BCS    ErrMakeTree
            LDA    tPosHi          ;Calculate position of new index block
            LSR                    ; in the top of the tree
            TAY
            LDA    scrtch          ;Get address of newly allocated index block again
            TAX
            STA    (tIndex),Y
            INC    tIndex+1
            LDA    scrtch+1
            STA    (tIndex),Y      ;Save hi address
            DEC    tIndex+1

            LDY    fcbPtr          ;Make newly allocated block the current index block
            STA    fcb+fcbIdxBlk+1,Y
            TXA
            STA    fcb+fcbIdxBlk,Y
            JSR    WrFCBFirst      ;Save new top of tree
            BCS    ErrMakeTree
            JMP    ZeroIndex       ;Zero index block in user's i/o buffer

*-------------------------------------------------
* Add new index blk

AddNewIdxBlk       JSR             GfcbStorTyp ;Find out if we're dealing with a tree
            CMP    #seedling       ;If seed then an adjustment to file type is necessary
            BEQ    SwapDown        ;Branch if seed
            JSR    RdFCBFst        ;Otherwise read in top of tree.
            BCC    MakeTree1       ;Branch if no error
ErrMakeTree RTS                    ;Return errors

* Add a higher index level to file

SwapDown    EQU    *               ;Make current seed into a sapling
            JSR    AllocWrBlk      ;Allocate a block before swap
            BCS    SwapErr         ;Return errors immediately
            LDY    fcbPtr          ;Get previous first block
            LDA    fcb+fcbFirst,Y  ; address into index block
            PHA                    ;Save temporarly while swapping in new top index
            LDA    scrtch          ;Get new block address (low)
            TAX
            STA    fcb+fcbFirst,Y
            LDA    fcb+fcbFirst+1,Y
            PHA
            LDA    scrtch+1        ; and high address too
            STA    fcb+fcbFirst+1,Y
            STA    fcb+fcbIdxBlk+1,Y;Make new top also the current index in memory
            TXA                    ;Get low address again
            STA    fcb+fcbIdxBlk,Y
            INC    tIndex+1        ;Make previous the first entry in sub index
            PLA
            STA    (tIndex)
            DEC    tIndex+1
            PLA
            STA    (tIndex)
            JSR    WrFCBFirst      ;Save new file top
            BCS    SwapErr
            JSR    GfcbStorTyp     ;Now adjust storage type by adding 1 
            ADC    #$01            ; (thus seed becomes sapling becomes tree)
            STA    fcb+fcbStorTyp,Y
            LDA    fcb+fcbStatus,Y ;Mark storage type modified
            ORA    #storTypMod
            STA    fcb+fcbStatus,Y
            CLC                    ;Return 'no error' status
SwapErr     RTS

*-------------------------------------------------

AllocWrBlk  JSR    Alloc1Blk       ;Allocate 1 block
            BCS    AlocErr
            JSR    GetFCBStat      ;Mark usage as modified
            ORA    #useMod
            STA    fcb+fcbStatus,Y
            LDA    fcb+fcbBlksUsed,Y;Bump current usage count by 1
            CLC
            ADC    #$01
            STA    fcb+fcbBlksUsed,Y
            LDA    fcb+fcbBlksUsed+1,Y
            ADC    #$00
            STA    fcb+fcbBlksUsed+1,Y
WrOK        CLC                    ;Indicate no error
AlocErr     RTS                    ;All done

*-------------------------------------------------
* Do Status if not I/O yet

TestWrProt  JSR    GetFCBStat      ;Check for a 'never been modified' condition
            AND    #useMod+dataMod+idxMod+eofMod
            BNE    WrOK            ;Ordinary RTS if known write ok

            LDA    fcb+fcbDevNum,Y ;Get file's device number
            STA    DevNum          ;Get current status of block device

* Status call

TestWrProtZ STA    unitNum         ;Make the device status call
            LDA    blockNum+1
            PHA
            LDA    blockNum        ;Save the current block values
            PHA
            STZ    dhpCmd          ;=statCmd
            STZ    blockNum        ;Zero the block #
            STZ    blockNum+1
            PHP
            SEI
            JSR    DMgr            ;Branch if write protect error
            BCS    :1
            LDA    #$00            ; Otherwise, assume no errors
:1          PLP                    ;Restore interrupt status
            CLC
            TAX                    ;Save error
            BEQ    :2              ;Branch if no error
            SEC                    ; else, set carry to show error
:2          PLA
            STA    blockNum        ;Restore the block #
            PLA
            STA    blockNum+1
            TXA
            RTS                    ;Carry is indeterminate