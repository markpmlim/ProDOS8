***********************************************************
* Close Call

Close       LDY    #c_refNum       ;Close all?
            LDA    (parm),Y
            BNE    Close1          ;No, just one of 'em
            STA    clsFlshErr      ;Clear global close error
            LDA    #$00            ;Begin at the beginning
ClsAll      STA    fcbPtr          ;Save current low byte of pointer
            TAY                    ;Fetch the level at which
            LDA    fcb+fcbLevel,Y  ; file was opened
            CMP    Level           ;Test against current global level
            BCC    NxtClose        ;Don't close if files level is < global level
            LDA    fcb+fcbRefNum,Y ;Is this reference file open?
            BEQ    NxtClose        ;No, try next
            JSR    FlushZ          ;Clean it out...
            BCS    ClosErr         ;Return flush errors

            JSR    CloseZ          ;Update FCB & VCB
            LDY    #c_refNum
            LDA    (parm),Y
            BEQ    NxtClose        ;No err if close all
            BCS    ClosErr
NxtClose    LDA    fcbPtr
            CLC
            ADC    #fcbSize
            BCC    ClsAll          ;Branch if within same page

            LDA    clsFlshErr      ;On final close of close all report logged errors
            BEQ    ClosEnd         ;Branch if errors
            RTS                    ;Carry already set (see BCC)

Close1      JSR    Flush1          ;Flush file first (including updating bit map)
            BCS    ClosErr         ;Report errors immediately!! 

CloseZ      LDY    fcbPtr
            LDA    fcb+fcbFileBuf,Y;Release file buffer 
            JSR    ReleaseBuf
            BCS    ClosErr
            LDA    #$00
            LDY    fcbPtr
            STA    fcb+fcbRefNum,Y ;Free file control block too
            LDA    fcb+fcbDevNum,Y
            STA    DevNum
            JSR    ScanVCB         ;Go look for associated VCB
            LDX    vcbPtr          ;Get vcbptr
            DEC    vcb+vcbOpenCnt,X;Indicate one less file open
            BNE    ClosEnd         ;Branch if that wasn't the last...
            LDA    vcb+vcbStatus,X
            AND    #$7F            ;Strip 'files open' bit
            STA    vcb+vcbStatus,X
ClosEnd     CLC
            RTS

ClosErr     BCS    FlushErr        ;Don't report close all err now 

Flush       LDY    #c_refNum       ;Flush all?
            LDA    (parm),Y
            BNE    Flush1          ;No, just one of 'em

            STA    clsFlshErr      ;Clear global flush error
            LDA    #$00            ;Begin at the beginning
:loop       STA    fcbPtr          ;Save current low byte of pointer
            TAY                    ;Index to reference number
            LDA    fcb+fcbRefNum,Y ;Is this reference file open?
            BEQ    :1              ;No, try next
            JSR    FlushZ          ;Clean it out..
            BCS    FlushErr        ;Return any errors
:1          LDA    fcbPtr          ;Bump pointer to next file control block
            CLC
            ADC    #fcbSize
            BCC    :loop           ;Branch if within same page

FlushEnd    CLC
            LDA    clsFlshErr      ;On last flush of a flush(0)
            BEQ    :Ret            ;Branch if no logged errors 
            SEC                    ;Report error now
:Ret        RTS

FlushZ      JSR    FndFCBuf        ;Must set up assoc vcb & buffer locations first
            BCC    Flush2a         ;Branch if no error encountered
FlushErr    JMP    GlbErr          ;Check for close or flush all

Flush1      STZ    clsFlshErr      ;Clear gbl flush error for normal refnum flush
            JSR    FindFCB         ;set up pointer to fcb user references
            BCS    FlushErr        ;return any errors

Flush2a     EQU    *               ;Test to see if file is modified
            LDA    fcb+fcbAttr,Y   ;First test write enabled
            AND    #writeEnable
            BEQ    FlushEnd        ;Branch if 'read only'
            LDA    fcb+fcbDirty,Y  ;See if eof has been modified
            BMI    :11             ;Branch if it has

            JSR    GetFCBStat      ;now test for data modified
            AND    #useMod+eofMod+dataMod; was written to while it's been open?
            BEQ    FlushEnd        ;Branch if file not modified

:11         JSR    GetFCBStat      ;Now test for data modified
            AND    #dataMod        ;Does current data buffer need
            BEQ    :12             ; to be written? Branch if not
            JSR    WrFCBData       ;If so, go write it stupid!
            BCS    FlushErr

:12         JSR    GetFCBStat      ;Check to see if the index block
            AND    #idxMod         ; (tree files only) needs to be written
            BEQ    :13             ;Branch if not...
            JSR    WrFCBIdx
            BCS    FlushErr        ;Return any errors

:13         LDA    #fcbEntNum      ;Now prepare to update directory
            TAX
            ORA    fcbPtr          ;(This should preserved Carry-bit)
            TAY
OwnerMov    LDA    fcb,Y           ;Note: this code depends on the
            STA    d_dev-1,X       ; defined order of the file control
            DEY                    ; block and the temporary directory
            DEX                    ; area in 'workspc'! *************
            BNE    OwnerMov

            STA    DevNum
            LDA    d_head          ;Read the directory header for this file
            LDX    d_head+1
            JSR    RdBlkAX         ;Read it into the general purpose buffer
            BCS    FlushErr        ;Branch if error
            JSR    MoveHeadZ       ;Move header info
            LDA    d_entBlk        ;Get address of directory block
            LDY    d_entBlk+1      ; that contains the file entry
            CMP    d_head          ;Test to see if it's the same block that
            BNE    FlsHdrBlk       ; the header is in. Branch if not
            CPY    d_head+1
            BEQ    Flush5          ;Branch if header block = entry block

FlsHdrBlk   STA    blockNum
            STY    blockNum+1
            JSR    RdGBuf          ;Get block with file entry in general buffer

Flush5      JSR    EntCalc         ;Set up pointer to entry
            JSR    MovEntry        ;Move entry to temp entry buffer in 'workspc'

            LDY    fcbPtr          ;Update 'blocks used' count
            LDA    fcb+fcbBlksUsed,Y
            STA    d_file+d_usage
            LDA    fcb+fcbBlksUsed+1,Y
            STA    d_file+d_usage+1;hi byte too...

            LDX    #$00            ;and move in end of file mark
EOFupdate   LDA    fcb+fcbEOF,Y    ; whether we need to or not
            STA    d_file+d_eof,X
            INX                    ;Move all three bytes
            CPX    #$03
            BEQ    :21
            LDA    fcb+fcbFirst,Y  ;Also move in the address of
            STA    d_file+d_first-1,X; the file's first block since
            INY                    ; it might have changed since the file
            BNE    EOFupdate       ; first opened. Branch always taken

:21         LDA    fcb+fcbStorTyp-2,Y;the last thing to update
            ASL                    ; is storage type (y=fcbPtr+2)
            ASL                    ;(shift it into the hi nibble)
            ASL
            ASL
            STA    scrtch
            LDA    d_file+d_stor   ;Get old type byte (it might be the same)
            AND    #$0F            ;Strip off old type
            ORA    scrtch          ;Add in the new type,
            STA    d_file+d_stor   ; & put it away
            JSR    ReviseDir       ;Go update directory!
            BCS    GlbErr

            LDY    fcbPtr          ;Mark
            LDA    fcb+fcbDirty,Y  ; FCB/directory
            AND    #$FF-fcbMod     ; as not
            STA    fcb+fcbDirty,Y  ; dirty
            LDA    d_dev           ;See if bitmap should be written
            CMP    bmaDev          ;Is it in same as current file?
            BNE    :22             ;Yes, put it on the disk if necessary
            JSR    UpdateBitMap    ;Go put it away
            BCS    GlbErr
:22         CLC
            RTS

GlbErr      LDY    #c_refNum       ;Report error immediately
            PHA                    ; only if not a close all or flush all
            LDA    (parm),Y
            BNE    :31             ;Not an 'all' so report now
            CLC
            PLA
            STA    clsFlshErr      ;Save for later
            RTS
:31         PLA
            RTS

* Get status of FCB
            
GetFCBStat  LDY    fcbPtr          ;Index to fcb
            LDA    fcb+fcbStatus,Y ;Return status byte
            RTS                    ;That is all...

SetErr      LDA    #invalidAccess
            SEC
EOFret      RTS

***********************************************************
* SETEOF Call

SetEOF      JSR    GfcbStorTyp     ;Only know how to move eof of tree, sapling, or seed
            CMP    #tree+1
            BCS    SetErr
            ASL
            ASL
            ASL
            ASL                    ;=$10,$20,$30
            STA    storType        ;May be used later for trimming the tree...
            LDA    fcb+fcbAttr,Y   ;Now check to insure write is enabled
            AND    #writeEnable    ;Can we set new eof?
            BEQ    SetErr          ;Nope, access error

            JSR    TestWrProt      ;Find out if mod is posible (H/W write protect)
            BCS    SetErr

            LDY    fcbPtr          ;Save old EOF
            INY
            INY
            LDX    #$02            ; so it can be seen
SetSave     LDA    fcb+fcbEOF,Y    ; whether blocks need
            STA    oldEOF,X        ; to be released
            DEY                    ; upon
            DEX                    ; contraction
            BPL    SetSave         ;All three bytes of the eof

            LDY    #c_eof+2
            LDX    #$02
NewEOFPos   LDA    (parm),Y        ;Position mark to new EOF
            STA    tPosll,X
            DEY
            DEX
            BPL    NewEOFPos

            LDX    #$02            ;Point to third byte
PurgeTest   LDA    oldEOF,X        ;See if EOF moved backwards
            CMP    tPosll,X        ; so blocks can
            BCC    EOFset          ; be released (branch if not)
            BNE    Purge           ;Branch if blocks to be released
            DEX
            BPL    PurgeTest       ;All three bytes

EOFset      LDY    #c_eof+2
            LDX    fcbPtr          ;Place new end of file into FCB
            INX
            INX
:loop       LDA    (parm),Y
            STA    fcb+fcbEOF,X
            DEX
            DEY
            CPY    #c_eof          ;All three bytes moved?
            BCS    :loop           ;Branch if not...
            JMP    FCBUsed         ;Mark fcb as dirty... all done

Purge       JSR    Flush1          ;Make sure file is current
            BCS    EOFret
            LDX    dataPtr+1       ;Restore pointer to index block
            INX
            INX                    ;(zero page conflict with dirPtr)
            STX    tIndex+1
            LDX    dataPtr
            STX    tIndex
            LDY    fcbPtr          ;Find out if eof < mark
            INY
            INY
            LDX    #$02
NewEOFtest  LDA    fcb+fcbMark,Y
            CMP    tPosll,X        ;Compare until not equal or carry clear
            BCC    SetEOF1         ;branch if eof>mark (mark is b4 new EOF)
            BNE    SetEOF0         ;branch if eof<mark
            DEY
            DEX
            BPL    NewEOFtest      ;Loop on all three bytes

SetEOF0     LDY    fcbPtr
            LDX    #$00
FakeEOF     LDA    tPosll,X        ;Fake position, correct position
            STA    fcb+fcbMark,Y
            INY                    ; will be made below...
            INX                    ;Move all three bytes
            CPX    #$03
            BNE    FakeEOF

SetEOF1     JSR    TakeFreeCnt     ;Force proper free blk cnt before releasing blocks
            LDA    tPosll          ;Now prepare for purge of excess blocks...
            STA    dSeed           ;All blocks and bytes beyond new 
            LDA    tPoslh          ; EOF must be zeroed! 
            STA    dSap
            AND    #$01
            STA    dSeed+1         ;(=0/1)
            LDA    tPosHi
            LSR
            STA    dTree
            ROR    dSap            ;Pass position in terms of block & bytes 
            LDA    dSeed           ;Now adjust for boundaries of $200
            ORA    dSeed+1         ;(block boundaries)
            BNE    SetEOF3         ;Branch if no adjustment necessary

            LDA    dSap            ;Get correct block positions
            SEC                    ; for sap & tree levels
            SBC    #$01
            STA    dSap            ;Deallocate for last (phantom) block
            LDA    #$02            ; & don't modify last data block
            BCS    SetEOF2         ;branch if tree level unaffected
            DEC    dTree           ;But if it is affected, make sure new eof # 0
            BPL    SetEOF2         ;Branch if new eof not zero

            LDA    #$00            ;Otherwise, just make a null seed out of it
            STA    dTree
            STA    dSap
SetEOF2     STA    dSeed+1         ;(On fall thru, =0 else = 2)
SetEOF3     LDY    fcbPtr          ;Also must pass file's first block addr
            LDA    fcb+fcbFirst,Y  ; which is its keyblk
            STA    firstBlkL
            LDA    fcb+fcbFirst+1,Y
            STA    firstBlkH

            STZ    deBlock         ;Lastly, number of blocks to be 
            STZ    deBlock+1       ; freed should be initialized
            JSR    DeTree          ;Go defoliate...
            PHP                    ;Save any error status until
            PHA                    ; FCB is cleaned up! 

            SEC
            LDY    fcbPtr
            LDX    #$00
AdjFCB      LDA    firstBlkL,X
            STA    fcb+fcbFirst,Y  ;Move in posible new first file block addr
            LDA    fcb+fcbBlksUsed,Y;Adjust usage count also
            SBC    deBlock,X
            STA    fcb+fcbBlksUsed,Y
            INY
            INX
            TXA
            AND    #$01            ;Test for both bytes adjusted 
            BNE    AdjFCB          ; without disturbing carry

            LDA    storType        ;get possibly modified storage type
            LSR
            LSR
            LSR
            LSR
            LDY    fcbPtr          ;save it in fcb
            STA    fcb+fcbStorTyp,Y
            JSR    ClrStats        ;Make it look as though position has 
            JSR    DvcbRev         ; nothing allocated, update total blocks in VCB

            LDY    fcbPtr          ;Now correct position stuff
            INY
            INY
            LDX    #$02
CorrectPos  LDA    fcb+fcbMark,Y   ;Tell RdPosn to go to correct
            STA    tPosll,X
            EOR    #$80            ; position from incorrect place
            STA    fcb+fcbMark,Y
            DEY
            DEX
            BPL    CorrectPos

            JSR    RdPosn          ;Go do it!!!
            BCC    Purge1          ;Branch if no error
            TAX                    ;Otherwise report latest error
            PLA
            PLP
            TXA                    ;Restore latest error code to stack
            SEC
            PHP
            PHA                    ;Save new error
Purge1      EQU    *               ;Mark file as in need of a flush and 
            JSR    EOFset          ; update FCB with new end of file
            JSR    Flush1          ;Now go do flush
            BCC    :1              ;Branch if no error

            TAX                    ;Save latest error
            PLA                    ;Clean previous error off stack
            PLP
            TXA                    ;Restore latest error code to stack
            SEC                    ;Set the carry to show error condition
            PHP                    ;Restore error status to stack
            PHA                    ; & the error code
:1          PLA                    ;Report any errors that may have cropped up
            PLP
            RTS

GetEOF      LDX    fcbPtr          ;Index to end of file mark
            LDY    #c_eof          ; & index to user's call parameters
OutEOF      LDA    fcb+fcbEOF,X
            STA    (parm),Y
            INX
            INY
            CPY    #c_eof+3
            BNE    OutEOF          ;Loop until all three bytes are moved
            CLC                    ;No errors
            RTS