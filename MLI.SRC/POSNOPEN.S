**************************************************
* GETMARK Call

GetMark     LDX    fcbPtr          ;Get index to open file control block
            LDY    #c_mark         ; & index to user's mark parameter
:loop       LDA    fcb+fcbMark,X
            STA    (parm),Y        ;Transfer current position
            INX                    ; to user's parameter list
            INY
            CPY    #c_mark+3       ;Have all three bytes been transferred?
            BNE    :loop           ;Branch if not...
            CLC                    ;No errors
            RTS

ErrMrkEOF   LDA    #outOfRange     ;Report invalid position.
            SEC
            RTS

**************************************************
* SETMARK Call

SetMark     LDY    #c_mark+2       ;Get index to user's desired position
            LDX    fcbPtr          ; & file's control block index
            INX                    ;(bump by 2 for index to hi EOF)
            INX
            SEC                    ;Indicate comparisons are necessary
:loop       LDA    (parm),Y        ;Move it to 'tPos'
            STA    tPosll-c_mark,Y
            BCC    :1              ;Branch if we already know mark<EOF
            CMP    fcb+fcbEOF,X    ;Carry or Z flag must be clear to qualify
            BCC    :1              ;Branch if mark qualifies for sure
            BNE    ErrMrkEOF       ;Branch if mark>EOF
            DEX

:1          DEY    dey             ;Prepare to move/compare next lower byte of mark
            TYA                    ;Test for all bytes moved/tested
            EOR    #c_mark-1       ;To preserve carry status
            BNE    :loop           ;Branch if more

* Still in same data block

RdPosn      LDY    fcbPtr          ;First test to see if new position is
            LDA    fcb+fcbMark+1,Y ; within the same (current) data block
            AND    #%11111110
            STA    scrtch          ;(At a block boundary)
            LDA    tPoslh          ;Get middle byte of new position
            SEC
            SBC    scrtch
            STA    scrtch
            BCC    TypMark         ;Branch if possibly l.t. current position
            CMP    #$02            ;Must be within 512 bytes of beginning of current
            BCS    TypMark         ;No
            LDA    tPosHi          ;Now make sure we're talking
            CMP    fcb+fcbMark+2,Y ; about the same 64K chunk!
            BNE    TypMark         ;Branch if we aren't
            JMP    SavMark         ;If we are, adjust FCB, posPtr and return

TypMark     EQU    *               ;Now find out which type
            LDA    fcb+fcbStorTyp,Y; of file we're positioning on
            BEQ    :11             ;There is no such type as zero, branch never!
            CMP    #tree+1         ;Is it a tree class file?
            BCC    TreePos         ;Yes, go position
            JMP    DirMark         ;No, test for directory type

:11         LDY    #fcbPtr         ;Clear illegally typed FCB entry
            STA    fcb+fcbRefNum,Y
            LDA    #invalidRefNum  ;Tell 'em there is no such file
            SEC
            RTS

* Need different data blk

TreePos     EQU    *               ;Use storage type as number of index levels
            LDA    fcb+fcbStorTyp,Y; (since 1=seed, 2=sapling, and 3=tree)
            STA    levels
            LDA    fcb+fcbStatus,Y ;Must not forget previous data
            AND    #dataMod        ;Therefore, see if previous data was modified
            BEQ    :21             ; then disk must be updated
            JSR    WrFCBData       ;Yes, so go write current data block
            BCS    PosErr          ;Return any error encountered

:21         LDY    fcbPtr          ;Test to see if current
            LDA    fcb+fcbMark+2,Y ; index block is going to be usable...
            AND    #%11111110      ; or in other words - is new position
            STA    scrtch          ; within 128K of the beginning
            LDA    tPosHi          ; of current sapling level chunk?
            SEC
            SBC    scrtch
            BCC    PosNew2         ;Branch if a new index block is also needed
            CMP    #$02            ;New position is > begining of old. Is it within 128K?
            BCS    PosNew2         ;Branch if not
            LDX    levels          ;Is the file we're dealing with a seed?
            DEX
            BNE    DataLevel       ;No, use current indexes

TestTiny    LDA    tPoslh          ;Is new position under 512?
            LSR
            ORA    tPosHi
            BNE    NoIdxData       ;No, mark both data and index block as un-allocated
            LDA    fcb+fcbFirst,Y  ;First block is only block and it's data!
            STA    blockNum
            LDA    fcb+fcbFirst+1,Y;(high block address)
            JMP    RdNewPos

PosNew2     EQU    *               ;Gota check to see if previous
            LDA    fcb+fcbStatus,Y ; index block was modified
            AND    #idxMod
            BEQ    PosnIdx         ;Read in over it if current is up to date
            JSR    WrFCBIdx        ;Go update index on disk (block addr in fcb)
            BCS    PosErr

PosnIdx     LDX    levels          ;Before reading in top index, check
            CPX    #tree           ; to be sure that there is a top index...
            BEQ    PosIndex        ;Branch if file is full blown tree

            LDA    tPosHi          ;Is new position within range
            LSR                    ; of a sapling file (l.t. 128k)?
            PHP                    ;Anticipate no good
            LDA    #topAloc+idxAloc+dataAloc;(to indicate no level is allocated for new posn)
            PLP                    ;Z flag tells all...
            BNE    NoData          ;Go mark 'em all dummy

            JSR    ClrStats        ;Go clear status bits 0,1,2 (index/data alloc status)
            DEX                    ;(unaffected since loaded above) Check for seed
            BEQ    TestTiny        ;If seed, check for position l.t. 512...

            JSR    RdFCBFst        ;Go get only index block
            BCS    PosErr          ;Branch if error

            LDY    fcbPtr          ;Save newly loaded index block's address
            LDA    blockNum
            STA    fcb+fcbIdxBlk,Y
            LDA    blockNum+1
            STA    fcb+fcbIdxBlk+1,Y
            BCC    DataLevel       ;Branch always...
PosErr      RTS                    ;Carry always set when branched to

PosIndex    JSR    ClrStats        ;Clear all allocation requirements for prev posn
            JSR    RdFCBFst        ;Get highest level index block
            BCS    PosErr

            LDA    tPosHi          ;Then test for a sap level index block
            LSR
            TAY
            LDA    (tIndex),Y
            INC    tIndex+1
            CMP    (tIndex),Y      ;(both hi and lo will be zero if no index exists)
            BNE    SapLevel
            TAX                    ;Are both bytes zero?
            BNE    SapLevel        ;No
            DEC    tIndex+1        ;Don't leave wrong pointers laying around!
NoIdxData   LDA    #idxAloc+dataAloc
            BRA    NoData

SapLevel    STA    blockNum        ;Read in next lower index block
            LDA    (tIndex),Y      ;(hi address)
            STA    blockNum+1
            DEC    tIndex+1
            JSR    RdFCBIdx        ;Read in sapling level
            BCS    PosErr

DataLevel   LDA    tPosHi          ;Now get block address of data block
            LSR
            LDA    tPoslh          ;( if there is one )
            ROR
            TAY
            LDA    (tIndex),Y      ;Data block address low
            INC    tIndex+1
            CMP    (tIndex),Y
            BNE    PosNew3
            TAX                    ;Are both bytes zero?
            BNE    PosNew3         ;No
            LDA    #dataAloc       ;Show data block has never been allocated
            DEC    tIndex+1

NoData      LDY    fcbPtr          ;Set status to show what's missing
            ORA    fcb+fcbStatus,Y
            STA    fcb+fcbStatus,Y
            LSR                    ;Throw away bit that says data block un-allocated
            LSR                    ; cuz we know that. Carry now indicates if index block
            JSR    ZipData         ; also is invalid and needs to be zeroed (Carry undisturbed)
            BCC    SavMark         ;Branch if index block doesn't need zipping

            JSR    ZeroIndex       ;Go zero index block in user's i/o buffer
            BRA    SavMark

ZeroIndex   LDA    #$00
            TAY
:loop1      STA    (tIndex),Y      ;Zero out the index half
            INY
            BNE    :loop1          ; of the user's i/o buffer
            INC    tIndex+1
:loop2      STA    (tIndex),Y
            INY
            BNE    :loop2          ;Restore proper address
            DEC    tIndex+1
            RTS                    ;That's all

ZipData     LDA    #$00            ;Also is invalid and needs to be zeroed
            TAY
:loop1      STA    (dataPtr),Y     ;Zero out data area
            INY
            BNE    :loop1
            INC    dataPtr+1
:loop2      STA    (dataPtr),Y
            INY
            BNE    :loop2
            DEC    dataPtr+1
            RTS

* Read file data blk

PosNew3     STA    blockNum        ;Get data block of new position
            LDA    (tIndex),Y      ;(hi address)
            DEC    tIndex+1
RdNewPos    STA    blockNum+1
            JSR    RdFCBData
            BCS    pritz           ;Return any error
            JSR    ClrStats        ;Show whole chain is allocated

* Got data blk wanted

SavMark     LDY    fcbPtr          ;Update position in file control block
            INY
            INY
            LDX    #$02
:loop       LDA    fcb+fcbMark,Y   ;Remember oldmark in case
            STA    oldMark,X       ; calling routine fails later
            LDA    tPosll,X        ;Set new mark
            STA    fcb+fcbMark,Y   ; in FCB
            DEY
            DEX                    ;Move 3-byte position marker
            BPL    :loop

            CLC                    ;Last, but not least, set up
            LDA    dataPtr         ; indirect address to buffer page pointed
            STA    posPtr          ; to by the current position marker
            LDA    tPoslh
            AND    #$01            ;(A)=0/1
            ADC    dataPtr+1       ;(posPtr) = start of pg in
            STA    posPtr+1        ; data blk which contains the mark
pritz       RTS                    ;Carry set indicates error!

*-------------------------------------------------
* Reset block allocate flags

ClrStats    LDY    fcbPtr          ;Clear allocation states for data block
            LDA    fcb+fcbStatus,Y ; and both levels of indexes
            AND    #$FF-topAloc-idxAloc-dataAloc
            STA    fcb+fcbStatus,Y ;This says that either they exist currently
            RTS                    ; or that they're unnecessary for current position.

*-------------------------------------------------
* Set dir file position

DirMark     CMP    #directoryFile  ;Is it a directory?
            BEQ    DirPos          ;Yes...
            LDA    #badFileFormat  ;No, there is a compatiblity problem -
            JSR    SysErr          ; the damn thing should never been opened!

DirPos      LDA    scrtch          ;Recover results of previous subtraction
            LSR                    ;Use difference as counter as to how many
            STA    cntEnt          ; blocks must be read to get to new position
            LDA    fcb+fcbMark+1,Y ;Test for position direction
            CMP    tPoslh          ;Carry indicates direction...
            BCC    DirFwrd         ;If set, position forward

DirReverse  LDY    #$00            ;Otherwise, read directory file in reverse order
            JSR    DirPos1         ;Read previous block
            BCS    DirPosErr       ;Branch if anything goes wrong
            INC    cntEnt          ;Count up to 128
            BPL    DirReverse      ;Loop if there is more blocks to pass over
            BMI    SavMark         ;Branch always

DirFwrd     LDY    #$02            ;Position is forward from current position
            JSR    DirPos1         ;Read next directory block
            BCS    DirPosErr
            DEC    cntEnt
            BNE    DirFwrd         ;Loop if position not found in this bloc
            BEQ    SavMark         ;Branch always

DirPos1     LDA    (dataPtr),Y     ;Get link address of previous
            STA    blockNum        ; or next directory block
            CMP    #$01            ; but first be sure there is a link
            INY
            LDA    (dataPtr),Y
            BNE    DirPos2
            BCS    DirPos2         ;Branch if certain link exists
            LDA    #eofEncountered ;Something is wrong with this directory file!
DirPosErr   SEC                    ;Indicate error
            RTS

DirPos2     STA    blockNum+1      ;(high order block address)
*
* Drop into rfcbdat (Read file's data block)
*
*
* Note: for directory positioning, no optimization has been done since
*   since directory files will almost always be less than 6 blocks.
*   If more speed is required or directory type files are to be used
*   for other purposes requiring more blocks, then the recommended
*   method is to call RdFCBData for the first block and go directly to
*   device (via jmp (iounitl)) handler for subsequent accesses.
*   Also note that no checking is done for read/write enable since a 
*   directory file can only be opened for read access.
*
RdFCBData   LDA    #rdCmd          ;Set read command
            STA    dhpCmd
            LDX    #dataPtr        ;Use X to point at address of data buffer
            JSR    FileIOZ         ;Go do file input
            BCS    :Ret            ;Return any error

            LDY    fcbPtr
            LDA    blockNum
            STA    fcb+fcbDataBlk,Y;Save block number just read in FCB
            LDA    blockNum+1
            STA    fcb+fcbDataBlk+1,Y
:Ret        RTS                    ;Carry set indicates error

*-------------------------------------------------
* Read sub index blk

RdFCBIdx    LDA    #rdCmd          ;Prepare to read in index bloc
            STA    dhpCmd
            LDX    #tIndex         ;Point at address of current index buffer
            JSR    FileIOZ         ;Go read index block
            BCS    :Ret            ;Report error
            LDY    fcbPtr
            LDA    blockNum
            STA    fcb+fcbIdxBlk,Y ;Save block address of this index in fcb
            LDA    blockNum+1
            STA    fcb+fcbIdxBlk+1,Y
            CLC
:Ret        RTS

*-------------------------------------------------
* Write key index blk

WrFCBFst1   LDA    #wrtCmd         ;Set write mode for device
            DB     $2C             ;Skip next 2 bytes for pseudo-branch always to RWFst

* Read key index blk

RdFCBFst    LDA    #rdCmd          ;Set read mode for device
RWFst       PHA                    ;Save command
            LDA    #fcbFirst
            ORA    fcbPtr          ;Add offset to fcbPtr
            TAY
            PLA
            LDX    #tIndex         ;Read block into index portion of file buffer
*
* Drop into DoFileIO
*
DoFileIO    STA    dhpCmd          ;Save command
            LDA    fcb,Y           ;Get disk block address from FCB
            STA    blockNum        ;Block zero not legal
            CMP    fcb+1,Y
            BNE    FileIO
            CMP    #$00            ;Are both bytes zero?
            BNE    FileIO          ;No, continue with request
            LDA    #badBlockErr    ;Otherwise report allocation error
            JSR    SysDeath        ;Never returns...

FileIO      LDA    fcb+1,Y         ;Get high address of disk block
            STA    blockNum+1

*-------------------------------------------------
* Set up and do file block I/O
* Entry
*  (X) = buf ptr in page zero

FileIOZ     PHP                    ;No interupts from here on out
            SEI
            LDA    $00,X           ;Get memory address of buffer from
            STA    bufPtr          ; zero page pointed to by
            LDA    $01,X           ; the X-register
            STA    bufPtr+1        ; & pass address to device handler

            LDY    fcbPtr
            LDA    fcb+fcbDevNum,Y ;Of course having the device number
            STA    DevNum          ; would make the whole operation more meaningful...
            LDA    #$FF            ;Also, set to
            STA    ioAccess        ; indicate reg call made to dev handler
            LDA    DevNum          ;xfer the device # for dispatcher to convert to unit #
            STA    unitNum
            STZ    SErr            ;Clear global error value
            JSR    DMgr            ;Call the driver
            BCS    :1              ;Branch if error
            PLP                    ;Restore interupts
            CLC
            RTS

:1          PLP                    ;Restore interupts
            SEC
            RTS

*-------------------------------------------------
* Check point bit map & write key blk

WrFCBFirst  JSR    UpdateBitMap    ;First update the bitmap 
            BRA    WrFCBFst1       ; and go write file's first block!

*-------------------------------------------------
* Check point data blk buffer

WrFCBData   LDX    #dataPtr
            LDA    #fcbDataBlk     ;Point at mem addr with X and disk addr with Y
            ORA    fcbPtr          ;Add offset to fcbptr
            TAY                    ; and put it in Y-reg
            LDA    #wrtCmd         ;Write data block
            JSR    DoFileIO
            BCS    FileIOerr       ;Report any errors
            LDA    #$FF-dataMod    ;Mark data status as current
            BRA    FCBUpdate

*-------------------------------------------------
* Check point index blk buffer

WrFCBIdx    JSR    UpdateBitMap    ;Go update bitmap 
            LDX    #tIndex         ;Point at address of index buffer
            LDA    #fcbIdxBlk      ; & block address of that index block
            ORA    fcbPtr
            TAY
            LDA    #wrtCmd
            JSR    DoFileIO        ;Go write out index block
            BCS    FileIOerr       ;Report any errors
            LDA    #$FF-idxMod     ;Mark index status as current
FCBUpdate   LDY    fcbPtr          ;Change status byte to
            AND    fcb+fcbStatus,Y ; reflect successful disk file update
            STA    fcb+fcbStatus,Y ;(carry is unaffected)
FileIOerr   RTS

**************************************************
* ProDOS8 OPEN Call

Open        JSR    FindFile        ;First of all look up the file...
            BCC    :1
            CMP    #badPathSyntax  ;Is an attempt to open a root directory?
            BNE    ErrOpen         ;No, pass back error
:1          JSR    TestOpen        ;Find out if any other files are writing
            BCC    Open1           ; to this same file. (branch if not)
ErrBusy     LDA    #fileBusy
ErrOpen     SEC
            RTS

WrgStorTyp  LDA    #badStoreType   ;Report file is of wrong storage type!
            SEC
            RTS

Open1       LDY    fcbPtr          ;Get address of first free FCB found
            LDA    fcbFlg          ;This byte indicates that a free FCB found
            BNE    AssignFCB       ; if non-zero is available for use
            LDA    #fcbFullErr     ;Report FCB full error
            SEC
            RTS

AssignFCB   LDX    #fcbSize-1      ;Assign fcb, but first
            LDA    #$00            ; clean out any old
ClrFCB      STA    fcb,Y           ; rubbish left around...
            INY
            DEX
            BPL    ClrFCB

            LDA    #fcbEntNum      ;Now begin claim by moving in file info 
            TAX                    ;Use X as source index
            ORA    fcbPtr
            TAY                    ; and Y as destination (FCB)
FCBOwner    LDA    d_dev-1,X       ;Move ownership information
            STA    fcb,Y           ;Note: this code depends upon the defined
            DEY                    ; order of both the FCB and directory entry
            DEX
            BNE    FCBOwner        ; buffer (d.). beware of changes!!! *************

            LDA    d_file+d_stor   ;Get storage type
            LSR                    ;Strip off file name length
            LSR
            LSR
            LSR                    ;(by dividing by 16)
            TAX                    ;Save in X for later type comparison
            STA    fcb+fcbStorTyp,Y; and in FCB for future access

            LDA    d_file+d_attr   ;Get files attributes & use
            AND    #readEnable+writeEnable; it as a default access request
            CPX    #directoryFile  ;If directory, don't allow write enable
            BNE    SavAttr1
            AND    #readEnable     ;(Read-only)
SavAttr1    STA    fcb+fcbAttr,Y
            AND    #writeEnable    ;Check for write enabled requested
            BEQ    :1              ;Branch if read only open
            LDA    totEnt          ;Otherwise, be sure no one else is reading
            BNE    ErrBusy         ; same file (set up by TestOpen)

:1          CPX    #tree+1         ;Is it a tree type file?
            BCC    :2              ;Test for further compatiblity. It must
            CPX    #directoryFile  ; be either a tree or a directory
            BNE    WrgStorTyp      ;Report file is of wrong storage type

:2          LDX    #$06            ;Move address of first block of file,
:loop1      STA    blockNum+1      ; end of file, and current usage count
            LDA    fcbPtr
            ORA    oFCBTbl,X       ;This is done via a translation
            TAY                    ; table between directory info and FCB
            LDA    d_file+d_first,X
            STA    fcb,Y
            DEX                    ;Has all info been moved? 
            BPL    :loop1

            STA    blockNum        ;Last loop stored hi addr of first block
            LDY    fcbPtr
            LDA    cntEnt          ;This was set up by 'TestOpen'...
            STA    fcb+fcbRefNum,Y ;Claim fcb for this file
            JSR    AllocBuf        ;Go allocate buffer in memtables
            BCS    ErrOpen2        ;Give up if any errors occurred

            JSR    FndFCBuf        ;Returns addrs of bufs in data & index pointers
            LDA    Level           ;Mark level at which
            STA    fcb+fcbLevel,Y  ; file was opened
            LDA    fcb+fcbStorTyp,Y;File must be positioned to beginning
            CMP    #tree+1         ;Is it a tree file?
            BCS    OpenDir         ;No, assume it's a directory
            LDA    #$FF            ;Fool the position routine into giving a
            STA    fcb+fcbMark+2,Y ; valid position with preloaded data, etc
            LDY    #$02            ;Set desired position to zero
            LDA    #$00
:loop2      STA    tPosll,Y
            DEY
            BPL    :loop2

            JSR    RdPosn          ;Let tree position routine do the rest
            BCC    OpenDone        ;Branch if successful

ErrOpen2    PHA                    ;Save error code
            LDY    fcbPtr          ;Return buffer to free space
            LDA    fcb+fcbFileBuf,Y
            BEQ    :1              ;Branch if no buf #

            JSR    ReleaseBuf      ;Doesn't matter if it was never allocated
            LDY    fcbPtr          ; since error was encountered before file
:1          LDA    #$00            ; was successfully opened, then
            STA    fcb+fcbRefNum,Y ; it's necessary to release FCB
            PLA
            SEC
            RTS

OpenDir     JSR    RdFCBData       ;Read in first block of directory file
            BCS    ErrOpen2        ;Return any error after freeing buffer & FCB
OpenDone    LDX    vcbPtr          ;Index to volume control block
            INC    vcb+vcbOpenCnt,X;Add 1 to the number of files currently open
            LDA    vcb+vcbStatus,X ; & indicate that this volume has
            ORA    #$80            ; at least 1 file active
            STA    vcb+vcbStatus,X

            LDY    fcbPtr          ;Index to file control block
            LDA    fcb+fcbRefNum,Y ;Return reference number to user
            LDY    #c_outRef
            STA    (parm),Y
            CLC                    ;Indicate successful open!
            RTS                    ;All done...

*-------------------------------------------------
* Test if file can be opened
* C=1
*  Already opened with write access
* NB. Multiple write access is not allowed
* C=0
*  File may be opened/already opened
*  If fcbFlag <> 0, got a free FCB &
*   (fcbPtr) = index into FCB table
* NB. Multiple read access is allowed

TestOpen    LDA    #$00
            STA    cntEnt          ;This temp returns the refnum of a free FCB
            STA    totEnt          ;This is used as a flag to indicate file is already open
            STA    fcbFlg          ;This is a flag to indicate a free FCB is available

TestOpen1   TAY                    ;Index to next FCB
            LDX    fcbFlg          ;Test for free FCB found
            BNE    :1              ;Branch if already found
            INC    cntEnt
:1          LDA    fcb+fcbRefNum,Y ;Is this FCB in use?
            BNE    ChkActive       ;Branch if it is
            TXA                    ;If not, should we claim it?
            BNE    TestNxtFCB      ;Branch if free FCB already found
            STY    fcbPtr          ;Save index to free FCB
            LDA    #-1             ;Set fcb flag to indicate free FCB found
            STA    fcbFlg
            BNE    TestNxtFCB      ;Branch always to test next FCB

ChkActive   TYA                    ;Add offset to index to ownership info
            ORA    #fcbEntNum
            TAY                    ;Put it back in Y-reg
            LDX    #fcbEntNum      ;Index to directory entry owner info
WhoOwns     LDA    fcb,Y
            CMP    d_dev-1,X       ;All bytes must match to say that its
            BNE    TestNxtFCB      ; the same file again
            DEY                    ;Index to next lower bytes
            DEX
            BNE    WhoOwns         ;Loop to check all owner info

            INC    totEnt          ;File is already open,
            LDA    fcb+fcbAttr,Y   ;Now see if it's already opened for write
            AND    #writeEnable
            BEQ    TestNxtFCB      ;Branch if this file is read access only
            SEC                    ;Multiple write access not allowed
            RTS

TestNxtFCB  TYA                    ;Calc position of next FCB
            AND    #%11100000      ;First strip any possible index offsets
            CLC
            ADC    #fcbSize        ;Bump to next FCB
            BNE    TestOpen1       ;Branch if more to compare
            CLC                    ;Report no conflicts
            RTS