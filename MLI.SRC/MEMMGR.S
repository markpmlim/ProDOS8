**************************************************
* Allocate I/O buf

AllocBuf    LDY    #c_bufPtr+1     ;Index to user specified buffer
AllocBufZ   LDA    (parm),Y        ;This buffer must be on a page boundary
            TAX                    ;Save in X-reg for validation
            CMP    #$08
            BCC    BadBufr         ;Cannot be lower than video!
            CMP    #$BC            ;Nor greater than $BB00
            BCS    BadBufr         ; since it would wipe out globals...
            STA    dataPtr+1
            DEY
            LDA    (parm),Y        ;Low addr should be zero!
            STA    dataPtr
            BNE    BadBufr         ;Branch if it isn't
            INX                    ;Add 4 pages for 1K buffer
            INX
            INX
            INX
:loop1      DEX                    ;Test for conflicts
            JSR    CalcMemBit      ;Test for free buffer space
            AND    memTabl,Y       ;Report memory conflict
            BNE    BadBufr         ; if any...
            CPX    dataPtr+1       ;Test all four pages
            BNE    :loop1
            INX                    ;Add 4 pages again for allocation
            INX
            INX
            INX

:loop2      DEX                    ;Set proper bits to 1
            JSR    CalcMemBit
            ORA    memTabl,Y       ; to mark it's allocation
            STA    memTabl,Y
            CPX    dataPtr+1       ;Set all four pages
            BNE    :loop2

            LDY    fcbPtr          ;Now calculate buffer number
            LDA    fcb+fcbRefNum,Y
            ASL                    ;buffer number=(entnum)*2
            STA    fcb+fcbFileBuf,Y;Save it in FCB
            TAX                    ;Use entnum*2 as index to global buffer addr tables
            LDA    dataPtr+1       ;Get addr already validated as good
            STA    GblBuf-1,X      ;Store hi addr (entnums start at 1, not zero)
            CLC
            RTS                    ;All done allocating buffers

BadBufr     LDA    #badBufErr      ;Tell user buf is in use or not legal otherwise
            SEC                    ;Indicate error
            RTS

**************************************************
* Locate ptr to I/O buf in global page

GetBufAdr   TAX                    ;Index into global buffer table
            LDA    GblBuf-2,X      ;Low buffer addr
            STA    bufAddrL
            LDA    GblBuf-1,X      ;and high addr
            STA    bufAddrH
            RTS

**************************************************
* Free I/O buf

ReleaseBuf  JSR    GetBufAdr       ;Preserve buf adr in 'bufAddr'
            TAY                    ;Returns high buffer addr in A
            BEQ    RelBufX         ;Branch if unallocated buffer space

            STZ    GblBuf-1,X      ;Take address out of buffer list
            STZ    GblBuf-2,X      ;(X was set up by GetBufAdr)

FreeBuf     LDX    bufAddrH        ;Get hi addr of buffer again
            INX                    ;Add 4 pages to account for 1k space
            INX
            INX
            INX
:loop       DEX                    ;Drop to next lower page
            JSR    CalcMemBit      ;Get bit and posn to memTabl of this page
            EOR    #$FF            ;Invert mask
            AND    memTabl,Y       ;Mark addr as free space now
            STA    memTabl,Y
            CPX    bufAddrH        ;All pages freed yet?
            BNE    :loop           ;Branch if not
RelBufX     CLC                    ;Indicate no error
            RTS

**************************************************
* Calculate memory allocation bit position
*  entry: (X)=hi addr of buffer, low addr assumed zero.
*
*  exit: (A)=allocation bit mask, (X)=unchanged,
*        (Y)=pointer to memTabl byte

CalcMemBit  TXA                    ;Move page address to A
            AND    #$07            ;Which page in any 2k set?
            TAY                    ;Use as index to determine
            LDA    WhichBit,Y      ; bit position representation
            PHA                    ;Save bit position mask for now
            TXA                    ;Get page address again
            LSR
            LSR                    ;Now determine 2K set
            LSR
            TAY                    ;Return it in Y
            PLA                    ;Restore bit mask
            RTS                    ;Return bit position in A&Y, ptr to memtabl in X

**************************************************
* Check buffer validity

ValDBuf     LDA    userBuf+1       ;Get high addr of user's buffer
            CMP    #$02            ;Must be greater than page 2
            BCC    BadBufr         ;Report bad buffer
            LDX    cBytes+1
            LDA    cBytes          ;Get cbytes-1 value
            SBC    #$01            ;(carry is set)
            BCS    :1
            DEX
:1          CLC
            ADC    userBuf         ;Calculate end of request addr
            TXA                    ;Do hi addr
            ADC    userBuf+1       ;All we care about is final addr
            TAX                    ;Must be less than $BF (globals)
            CPX    #$BF
            BCS    BadBufr
            INX                    ;Loop thru all  affected pages

ValDBufZ    DEX                    ;Check next lower page
            JSR    CalcMemBit
            AND    memTabl,Y       ;If zero then no conflict
            BNE    BadBufr         ;Branch if conflict...
            CPX    userBuf+1       ;Was that the last (lowest) page?
            BNE    ValDBufZ        ;Branch if not
            CLC                    ;Indicate all pages ok
            RTS                    ;All done here

**************************************************
* GETBUF Call

GetBuf      LDY    #c_bufAdr       ;Give user address of file buffer
            LDA    bufAddrL        ; referenced by refnum
            STA    (parm),Y
            INY
            LDA    bufAddrH
            STA    (parm),Y        ;No errors possible if this rtn is called
            CLC
            RTS

**************************************************
* SETBUF Call

SetBuf      LDY    #c_bufAdr+1
            JSR    AllocBufZ       ;Allocate new buffer address over old one
            BCS    SetBufErr       ;Report any conflicts immediately

            LDA    bufAddrH
            STA    userBuf+1
            LDA    bufAddrL
            STA    userBuf
            JSR    FreeBuf         ;Now free address space of old buffer

            LDY    #$00
            LDX    #$03
:loop       LDA    (userBuf),Y     ;Move all four pages of
            STA    (dataPtr),Y     ; the buffer to new location
            INY
            BNE    :loop
            INC    dataPtr+1
            INC    userBuf+1
            DEX
            BPL    :loop
            CLC
SetBufErr   RTS

**************************************************
*
*  This is the routine that moves the 3 pages of dispatcher 1
*  from $D100 of the alt 4k bank to its execution address ($1000).
*  Since it is in the MLI and must swap the $D000-$DFFF banks,
*  it must be resident at all times above $E000.
*
**************************************************

* NB. There is a vector @ $FEFD which points to this rtn

CallDisp    LDA    LCBANK2
            LDA    LCBANK2         ;Bring in the other $D000 space
            LDA    #>DispAdr       ;Destination address of user-code
            STA    A2+1
            LDA    #<DispAdr
            STA    A2
            LDA    #$D1            ;Dispatcher is stored at $D100-$D3FF
            STA    A1+1
            STZ    A1

            LDY    #$00
            LDX    #$03            ;3 pages of code to move
MovPage     DEY                    ;Nifty routine to move a page of code
            LDA    (A1),Y          ;Move all 255 bytes on the page
            STA    (A2),Y
            TYA
            BNE    MovPage
            INC    A1+1            ;Move pointers to next page
            INC    A2+1
            DEX
            BNE    MovPage

            LDA    LCBANK1
            LDA    LCBANK1         ;Swap MLI's $D000 space back in

            STZ    mliActv
            STZ    SOFTEV          ;Set up the reset vector
            LDA    #>DispAdr
            STA    SOFTEV+1        ; to dispatch entry
            EOR    #$A5            ;Set up power up byte
            STA    PWREDUP
            JMP    DispAdr

**************************************************
* Handles calls to mirror devices
* ProDOS unit #s are of the form DSSS xxxx
* where the bits of the low nibble are the 
* attributes of the device.
* D=0/1 (drive 1/drive 2)
* The handler only supports 14 mirror devices
* A statusCmd ($00) call will return the #
* of blocks in (Y,X)

MirrorDevEntry     LDX             #$03 ;Default parm cnt
            LDA    dhpCmd          ;Get cmd
            STA    spCmdNum
            BNE    :1

            LDY    #<spStatList    ;Its a statusCmd
            STY    bufPtr
            LDY    #>spStatList
            STY    bufPtr+1
            STZ    blockNum
:1          CMP    #$03            ;FormatCmd?
            BNE    :2              ;No

            LDX    #$01            ;parm cnt for a formatCmd
:2          STX    spCmdList
            LDA    unitNum         ;(dsss 0000)
            LSR
            LSR
            LSR
            LSR
            TAX                    ;0000 dsss ($01-$0F; $00,$08,$0B-invalid)
            LDA    spUnits-1,X     ;Get actual SP unit # which
            STA    spUnitNum       ; corr to this ProDOS unit #
            LDA    spDrvAdrL-1,X
            STA    CallSPort+1     ;Get addr of SP dev driver
            LDA    spDrvAdrH-1,X
            STA    CallSPort+2     ; which handles this SP unit

            LDX    #$04
:CpyLoop    LDA    bufPtr-1,X
            STA    blkIOParms-1,X
            DEX
            BNE    :CpyLoop

CallSPort   JSR    $0000           ;Go do it!
spCmdNum    DB     $00
            DA     spCmdList
            BCS    :Rtn

            LDX    spCmdNum        ;Was a SP STATUS call executed?
            BNE    :Rtn            ;No
            LDX    spDevTotBlks    ;# of blocks
            LDY    spDevTotBlks+1
            LDA    genStatus
            BIT    #$10            ;Is dev online/disk in drive?
            BNE    :1              ;Yes
            LDA    #drvrOffLine
            BRA    :2

:1          AND    #$44            ;Retain bits 6,2
            EOR    #$40            ;Is it write-protected?
            BEQ    :Rtn            ;No
            LDA    #drvrWrtProt
:2          SEC
:Rtn        RTS

*-------------------------------------------------
* This table was built during a P8 boot

spDrvAdrL   DS     $F,0            ;Actual entry points
spDrvAdrH   DS     $F,0            ; of a device's driver

* Command List used for all 4 commands viz
* 0-Status, 1-Read Block, 2-Write Block, 3-Format
* The caller must pass the parms using the
* usual zp locations $42-$47

spCmdList   DB     $03             ;parm count
spUnitNum   DB     $00             ;unit #
blkIOParms  DA     $0000           ;Data I/O buf
blokNum     DB     0,0,0           ;blk # (only 2 bytes used)