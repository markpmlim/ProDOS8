****************************
*                          *
*    read address field    *
*        subroutine        *
*    (16-sector format)    *
*                          *
****************************
*                          *
*    reads volume, track   *
*        and sector        *
*                          *
*    on entry ----     *
*                          *
*  xreg: slotnum times $10 *
*                          *
*  read mode (q6l, q7l)    *
*                          *
*    on exit -----     *
*                          *
*  carry set if error.     *
*                          *
*  if no error:            *
*    a-reg holds $aa.      *
*    y-reg holds $00.      *
*    x-reg unchanged.      *
*    carry clear.          *
*                          *
*    csstv holds chksum,   *
*      sector, track, and  *
*      volume read.        *
*                          *
*    uses temps count,     *
*      last, csum, and     *
*      4 bytes at csstv.   *
*                          *
*     expects ----     *
*                          *
*   original 10-sector     *
*  normal density nibls    *
*   (4-bit), odd bits,     *
*   then even.             *
*                          *
*     caution ----     *
*                          *
*         observe          *
*    'no page cross'       *
*      warnings on         *
*    some branches!!       *
*                          *
*     assumes ----     *
*                          *
*    1 usec cycle time     *
*                          *
****************************

RdAdr16     LDY    #$FC
            STY    count           ;'must find' count
RdASyn      INY
            BNE    :loop1          ;Low order of count
            INC    count           ;(2k nibbles to find
            BEQ    RdErr           ; adr mark, else err)
:loop1      LDA    q6l,X           ;Read nibble
            BPL    :loop1          ;*** no page cross! ***
RdASyn1     CMP    #$D5            ;Adr mark 1?
            BNE    RdASyn          ;(loop if not)
            NOP                    ;Added nibble delay
            LDA    q6l,X
            BPL    *-3             ;*** no page cross! ***
            CMP    #$AA            ;Adr mark 2?
            BNE    RdASyn1         ; (if not, is it am1?)
*            (added nibl delay)
            LDY    #$03            ;Index for 4-byte read
            LDA    q6l,X
            BPL    *-3             ;*** no page cross! ***
            CMP    #$96            ;Adr mark 3?
            BNE    RdASyn1         ; (if not, is it am1?)
            SEI                    ;No interupts until address is tested.(carry is set)
            LDA    #$00            ;Init checksum
RdAddrFld   STA    chkSum
            LDA    q6l,X           ;Read 'odd bit' nibble
            BPL    *-3             ;*** no page cross! ***
            ROL                    ;Align odd bits, '1' into lsb
            STA    last            ; (save them)
            LDA    q6l,X           ;Read 'even bit' nibble
            BPL    *-3             ;*** no page cross! ***
            AND    last            ;Merge odd and even bits
            STA    csSTV,Y         ;Store data byte
            EOR    chkSum
            DEY
            BPL    RdAddrFld       ;Loop on 4 data bytes
            TAY                    ;If final checksum
            BNE    RdErr           ; nonzero, then error
            LDA    q6l,X           ;First bit-slip nibble
            BPL    *-3             ;*** no page cross! ***
            CMP    #$DE
            BNE    RdErr           ;Error if nonmatch
            NOP                    ;delay
            LDA    q6l,X           ;Second bit-slip nibble
            BPL    *-3             ;*** no page cross! ***
            CMP    #$AA
            BNE    RdErr           ;Error if nonmatch
            CLC                    ;Clear carry on
            RTS                    ;Normal read exits

RdErr       SEC
            RTS
**************************
*                        *
*     read subroutine    *
*   (16-sector format)   *
*                        *
**************************
*                        *
*   reads encoded bytes  *
*  into nbuf1 and nbuf2  *
*                        *
*  first reads nbuf2     *
*          high to low,  *
*  then reads nbuf1      *
*          low to high.  *
*                        *
*    on entry ----   *
*                        *
*  x-reg: slotnum        *
*         times $10.     *
*                        *
*  read mode (q6l, q7l)  *
*                        *
*    on exit -----   *
*                        *
*  carry set if error.   *
*                        *
*  if no error:          *
*     a-reg holds $aa.   *
*     x-reg unchanged.   *
*     y-reg holds $00.   *
*     carry clear.       *
*    caution -----   *
*                        *
*        observe         *
*    'no page cross'     *
*      warnings on       *
*    some branches!!     *
*                        *
*    assumes ----    *
*                        *
*   1 usec cycle time    *
*                        *
**************************

Read16      TXA                    ;Get slot #
            ORA    #$8C            ;Prepare mods to read routine
            STA    Read4+1         ;Warning: the read routine is self modified!!!
            STA    Read5+1
            STA    Read6+1
            STA    Read7+1
            STA    Read8+1
            LDA    bufPtr          ;Modify storage addresses also
            LDY    bufPtr+1
            STA    Ref3+1
            STY    Ref3+2
            SEC
            SBC    #$54
            BCS    :1
            DEY
:1          STA    Ref2+1
            STY    Ref2+2
            SEC
            SBC    #$57
            BCS    :2              ;Branch if no borrow
            DEY
:2          STA    Ref1+1
            STY    Ref1+2
            LDY    #$20            ;'must find count'
rSync       DEY
            BEQ    RdErr2          ;Branch if can't find data header marks
            LDA    q6l,X
            BPL    *-3
rSync1      EOR    #$D5            ;First data mark
            BNE    rSync
            NOP                    ;Waste a little time...
            LDA    q6l,X
            BPL    *-3
            CMP    #$AA            ;Data mark 2
            BNE    rSync1          ;If not, check for first again
            NOP
            LDA    q6l,X
            BPL    *-3
            CMP    #$AD            ;Data mark 3
            BNE    rSync1          ;If not, check for data mark 1 again
            LDY    #$AA
            LDA    #$00
RdData1     STA    wTemp           ;Use zpage for checksum keepin
Read4       LDX    $C0EC           ;Warning: self modified
            BPL    Read4
            LDA    dNibble,X
            STA    nBuf2-$AA,Y     ;Save the two-bit groups in nbuf
            EOR    wTemp           ;Update checksum
            INY                    ;Bump to next nBuf2 position
            BNE    RdData1         ;Loop for all $56 two-bit groups
            LDY    #$AA            ;Now read directly into user buffer
            BNE    Read5           ;Branch always taken!!!
RdErr2      SEC
            RTS

Ref1        STA    $1000,Y         ;Warning: self modified!

Read5       LDX    $C0EC
            BPL    Read5
            EOR    dNibble,X       ;Get actual 6-bit data from dNibble table
            LDX    nBuf2-$AA,Y     ;Get associated two-bit pattern
            EOR    dNibble2,X      ; & combine to form whole byte
            INY
            BNE    Ref1            ;Loop for $56 bytes
            PHA                    ;Save this byte for now, no time to store...
            AND    #$FC            ;Strip low 2 bits...
            LDY    #$AA            ;Prepare for next $56 bytes
Read6       LDX    $C0EC
            BPL    Read6
            EOR    dNibble,X
            LDX    nBuf2-$AA,Y
            EOR    dNibble3,X
Ref2        STA    $1000,Y         ;Warning: self modified
            INY
            BNE    Read6           ;Loop until this group of $56 read in
*
Read7       LDX    $C0EC
            BPL    Read7
            AND    #$FC
            LDY    #$AC            ;Last group is $54 long
RdData2     EOR    dNibble,X
            LDX    nBuf2-$AC,Y
            EOR    dNibble4,X      ;Combine to form full byte
Ref3        STA    $1000,Y
Read8       LDX    $C0EC           ;Warning: self modified
            BPL    Read8
            INY
            BNE    RdData2
            AND    #$FC
            EOR    dNibble,X       ;Check sum ok?
            BNE    RdErr1          ;Branch if not
            LDX    slotZ           ;Test end marks
            LDA    q6l,X
            BPL    *-3
            CMP    #$DE
            CLC
            BEQ    RdOK            ;Branch if good trailer...
RdErr1      SEC
RdOK        PLA
            LDY    #$55            ;Place last byte into user buffer
            STA    (bufPtr),Y
            RTS

* This subroutine sets the slot
*  dependent track location.

SetTrk      JSR    DrvIndx         ;Get index to drive number
            STA    drv0Trk,X
            RTS
*****************************************
*
* Subrtn to tell if motor is stopped
*
* If motor is stopped, controller's
* shift reg will not be changing.
*
* return y=0 and zero flag set if it is stopped.
*
*****************************************
ChkDrv      LDX    slotZ
ChkDrv0     LDY    #$00            ;init loop counter
:loop       LDA    q6l,X           ;read the shift reg
            JSR    :ChkDrvRTS      ;delay
            PHA
            PLA                    ;more delay
            CMP    q6l,X
            BNE    :ChkDrvRTS
            LDA    #$28
            DEY
            BNE    :loop
:ChkDrvRTS  RTS

DrvIndx     PHA                    ;Preserve Acc
            LDA    unitNum         ;DSSS xxxx where D=0/1 & SSS=slot #
            LSR
            LSR
            LSR
            LSR                    ;0000 DSSS
            CMP    #$08            ;C=1 -> drive 2
            AND    #$07            ;0000 0SSS
            ROL                    ;0000 SSSD
            TAX                    ;Into X for index to table
            PLA                    ;Restore A
            RTS
************************
*                      *
*      write subr      *
*  (16-sector format)  *
*                      *
************************
*                      *
*   writes data from   *
*    nbuf1 and buf     *
*                      *
*  first nbuf2,        *
*      high to low.    *
*  then direct from    *
*  (buf), low to high. *
* self modified code!! *
*   on entry ----  *
*                      *
*   x-reg: slotnum     *
*        times $10.    *
*                      *
*                      *
*   on exit -----  *
*                      *
*  carry set if error. *
*   (w prot violation) *
*                      *
*  if no error:        *
*                      *
*    a-reg uncertain.  *
*    x-reg unchanged.  *
*    y-reg holds $00.  *
*    carry clear.      *
*                      *
*   assumes ----   *
*                      *
*  1 usec cycle time   *
*                      *
************************

Write16     SEC                    ;Anticipate wprot err
            LDA    q6h,X
            LDA    q7l,X           ;Sense wprot flag
            BPL    :1
            JMP    WExit           ;Exit if write protected

:1          LDA    nBuf2
            STA    wTemp
            LDA    #$FF            ;Sync data
            STA    q7h,X           ;(5) Goto write mode
            ORA    q6l,X           ;(4)
            LDY    #$04            ;(2) For five nibbles
            NOP                    ;(2)
            PHA                    ;(3)
            PLA                    ;(4)
WSync       PHA                    ;(3) exact timing
            PLA                    ;(4) exact timing
            JSR    WrNibl7         ;(13,9,6)  write sync
            DEY                    ;(2)
            BNE    WSync           ;(3-)  must not cross page!
            LDA    #$D5            ;(2)  1st data mark
            JSR    WrNibl9         ;(15,9,6)
            LDA    #$AA            ;(2)  2nd data mark
            JSR    WrNibl9         ;(15,9,6)
            LDA    #$AD            ;(2)  3rd data mark
            JSR    WrNibl9         ;(15,9,6)
            TYA                    ;(2) zero checksum
            LDY    #$56            ;(2) nbuf2 index
            BNE    wData1          ;(3) branch always taken
wData0      LDA    nBuf2,Y         ;(4) prior 6-bit nibble
wData1      EOR    nBuf2-1,Y       ;(5) xor with current
            TAX                    ;(2) index to 7-bit nibl (nBuf2 must be on page bdry)
            LDA    Nibbles,X       ;(4) must not cross page boundary
            LDX    slotZ           ;(3) restore slot index
            STA    q6h,X           ;(5) store encoded byte
            LDA    q6l,X           ;(4) time must = 32 us per byte!
            DEY                    ;(2)
            BNE    wData0          ;(3-) must not cross page boundary
            LDA    wTemp           ;(3) get prior nibble (from nBuf2)
WRefDr1     LDY    #$00            ;(2) warning: load value modified by prenib!
WData2      EQU    *
WRefAdr1    EOR    $1000,Y         ;(4) warning: address modified by prenib!
            AND    #$FC            ;(2)
            TAX                    ;(2) index to Nibbles table
            LDA    Nibbles,X       ;(4)
WRefDr2     LDX    #$60            ;(2) warning: load value modified by prenib
            STA    q6h,X           ;(5) write nibl
            LDA    q6l,X           ;(4) handshake
WRefAdr2    LDA    $1000,Y         ;(4) prior nibl. warning: address modified by prenib
            INY                    ;(2) all done with this page?
            BNE    WData2          ;(3-) loop until page end

            LDA    midNib1         ;(3) get next (precalculated and translated) nibl
            BEQ    WrtDone         ;(2+) branch if code writen was page aligned
            LDA    yEnd            ;(3) get byte address of last byte to be written
            BEQ    WData4          ;(2+) branch if only 1 byte left to write
            LSR                    ;(2) test for odd or even last byte (carry set or clear)
            LDA    midNib1         ;(3) restore nibl to a
            STA    q6h,X           ;(5)
            LDA    q6l,X           ;(4)
            LDA    midNib2         ;(3) =byte 0 of second page. xor'd with byte 1 if above test set carry
            NOP                    ;(2) waste time
            INY                    ;(2) y=1
            BCS    WrtOdd          ;(2+) branch if last byte to be odd

WData3      EQU    *
WRefAdr3    EOR    $1100,Y         ;(4) warning: address modified by prenib
            AND    #$FC            ;(2) strip low 2 bits
            TAX                    ;(2) index to Nibbles table
            LDA    Nibbles,X       ;(4) get nibble
WRefDr3     LDX    #$60            ;(2) restore slot index. warning: modified by prenib
            STA    q6h,X           ;(5)
            LDA    q6l,X           ;(4)
WRefAdr4    LDA    $1100,Y         ;(4) warning: modified by prenib
            INY                    ;(2) got prior nibble, bump to next
WRefAdr5    EOR    $1100,Y         ;(4) warning: modified by prenib
WrtOdd      CPY    yEnd            ;(3) set carry if this is last nibble
            AND    #$FC            ;(2)
            TAX                    ;(2)
            LDA    Nibbles,X       ;(4)
WRefDr4     LDX    #$60            ;(2) restore slot. warning: modified by prenib
            STA    q6h,X           ;(5)
            LDA    q6l,X           ;(4)
WRefAdr6    LDA    $1100,Y         ;(4) get prior. warning: these warnings are all the same
            INY                    ;(2)
            BCC    WData3          ;(3-) branch if that was not the las
            BCS    *+2             ;(3) waste 3 cycles, branch always
            BCS    WrtDone         ;(3) branch always

WData4      LDA    |midNib1        ;(4) absolute reference to zero page
            STA    q6h,X           ;(5)
            LDA    q6l,X           ;(4)
            PHA                    ;(3) waste 14 us total
            PLA                    ;(4)
            PHA                    ;(3)
            PLA                    ;(4)
WrtDone     LDX    lstNib          ;(3) use last nibl (anded with $fc) for checksum
            LDA    Nibbles,X       ;(4)
WRefDr5     LDX    #$60            ;(2) restore slot. warning: see above warnings...
            STA    q6h,X           ;(5)
            LDA    q6l,X           ;(4)
            LDY    #$00            ;(2) set y to index end mark table
            PHA                    ;(3) waste another 11 us
            PLA                    ;(4)
            NOP                    ;(2)
            NOP                    ;(2)
WrEndMrk    LDA    EndMarks,Y      ;(4) dm4, dm5, dm6, and turn off byte
            JSR    WrNibl          ;(15,6)    write it
            INY                    ;(2)
            CPY    #$04            ;(2) have all end marks been written?
            BNE    WrEndMrk        ;(3)
            CLC                    ;(2,9)
WExit       LDA    q7l,X           ;Out of write mode
            LDA    q6l,X           ;Into read mode
            RTS                    ;Return from write
****************************
*                           *
*   7-bit nibl write subrs  *
*                           *
*   a-reg or'd prior exit   *
*       carry cleared       *
*                           *
****************************

WrNibl9     CLC                    ;(2)  9 cycles, then write
WrNibl7     PHA                    ;(3)  7 cycles, then write
            PLA                    ;(4)
WrNibl      STA    q6h,X           ;(5)  nibble write subrtn
            ORA    q6l,X           ;(4)  clobbers acc, not carry
            RTS                    ;(6)
****************************
*                          *
*    preniblize subr       *
*   (16-sector format)     *
*                          *
****************************
*                          *
*  converts 256 bytes of   *
*  user data in (buf) into *
*  6 bit nibls into nbuf2  *
*  high 6 bits are trans-  *
*  lated directly by the   *
*  write routines.         *
*                          *
*     on entry ----    *
*                          *
*  buf is 2-byte pointer   *
*    to 256 bytes of user  *
*    data.                 *
*                          *
*     on exit -----    *
*                          *
*  a,x,y undefined.        *
*  write routine modified  *
*  to do direct conversion *
*  of high 6 bits of users *
*  buffer data.            *
****************************

PreNibl16   LDA    bufPtr          ;First self modify addresses so we can be fast!
            LDY    bufPtr+1        ;Y contains high order address
            CLC                    ;All offsets are -$AA...
            ADC    #$02            ;The highest set is bufPtr+$AC
            BCC    :1              ;Branch if no carry
            INY                    ;Otherwise add carry to high address
:1          STA    PrN3+1          ;Self mod 3
            STY    PrN3+2
            SEC
            SBC    #$56            ;middle set is buf+$56
            BCS    :2              ;branch if no borrow
            DEY                    ;otherwise deduct from high...
:2          STA    PrN2+1          ;self mod 2
            STY    PrN2+2
            SEC
            SBC    #$56            ;Low set is exactly bufPtr
            BCS    :3
            DEY
:3          STA    PrN1+1          ;self mod 1
            STY    PrN1+2

            LDY    #$AA            ;Count up to 0
PreNib4     EQU    *
PrN1        LDA    $1000,Y         ;Fetch byte from lowest group. warning: self modified
            AND    #%00000011      ;Strip high 6 bits
            TAX                    ;Index to 2 bit equiv
            LDA    TwoBit1,X
            PHA                    ;save pattern
PrN2        LDA    $1056,Y         ;fetch from middle group
            AND    #%00000011
            TAX
            PLA                    ;Restore pattern
            ORA    TwoBit2,X       ;Combine second group with first
            PHA                    ;Save new pattern
PrN3        LDA    $10AC,Y         ;Get highest group
            AND    #%00000011
            TAX
            PLA                    ;Restore new pattern
            ORA    TwoBit3,X       ; & form final nibble
            PHA
            TYA
            EOR    #$FF
            TAX
            PLA
            STA    nBuf2,X         ;Save in nibble buffer!
            INY                    ;Bump to next set
            BNE    PreNib4         ;Loop until all $56 nibbles formed
            LDY    bufPtr          ;Now prepare data bytes for write16 routine
            DEY                    ;Prepare end addr
            STY    yEnd
            LDA    bufPtr
            STA    WRefDr1+1       ;warning: the following storage addresses starting
            BEQ    WrMod1          ; with 'wref' are referces into code space,
            EOR    #$FF            ; changed by this routine
            TAY                    ;Index to last byte of page pointed to by buf
            LDA    (bufPtr),Y      ;Pre-niblize the last byte of the page with
            INY                    ; the first byte of the next page
            EOR    (bufPtr),Y
            AND    #$FC
            TAX
            LDA    Nibbles,X       ;Get disk 7-bit nibble equivalent
WrMod1      STA    midNib1
            BEQ    WrMod3          ;Branch if data to be written is page aligned
            LDA    yEnd            ;Find out if last byte is even or odd address
            LSR                    ;Shift even/oddness into carry
            LDA    (bufPtr),Y      ;If even, then leave intact
            BCC    WrMod2          ;Branch if odd
            INY                    ;If even, then pre-xor with byte 1
            EOR    (bufPtr),Y
WrMod2      STA    midNib2         ;Save result for write routine
WrMod3      LDY    #$FF            ;Index to last byte of data to be writen
            LDA    (bufPtr),Y      ; to be used as checksum
            AND    #$FC            ;Strip extra bits
            STA    lstNib          ;Save it
            LDY    bufPtr+1        ;Now modify address reference to user data
            STY    WRefAdr1+2
            STY    WRefAdr2+2
            INY
            STY    WRefAdr3+2
            STY    WRefAdr4+2
            STY    WRefAdr5+2
            STY    WRefAdr6+2
            LDX    slotZ           ; & lastly index references to controller
            STX    WRefDr2+1
            STX    WRefDr3+1
            STX    WRefDr4+1
            STX    WRefDr5+1
            RTS                    ;All done

ChkPrev     EOR    iobPrevDn       ;Same slot as last?
            ASL
            BEQ    :Rtn            ;Yes
            LDA    #$01
            STA    monTimeH
:CkLoop     LDA    iobPrevDn       ;=DSSS xxxx
            AND    #$70            ;=0SSS 0000
            TAX
            BEQ    :Rtn            ;Branch if no previous ever (boot only)
            JSR    ChkDrv0         ;Find out if previous drive running
            BEQ    :Rtn            ;Branch if stopped
            LDA    #$01            ;Waste some time
            JSR    msWait
            LDA    monTimeH
            BNE    :CkLoop
:Rtn        RTS

* ----------------- see rev notes 14, 18 & 70 -------------

ResetPhase  LDA    unitNum         ;Get unit number
            AND    #$7F            ;Map off hi bit (drive bit)
            TAX

* clear all the phases and force read mode
* patch 76 part 2. part 1 is in xrw1.

            LDA    phaseOff,X      ;make sure all motor
            LDA    phaseOff+2,X    ; phases are off
            LDA    phaseOff+4,X
            LDA    phaseOff+6,X
            RTS

* ---------------------------------------------------------
doCheck     LDA    dhpCmd          ;Get the command number
            CMP    #maxCmd         ;Is the command allowable?
            BCS    doChkBad        ;Branch if not!
            LDA    blockNum
            LDX    blockNum+1
            STX    ibTrk           ;Calculate block's track & sector
            BEQ    doChkOK         ;Branch if block # in range
            DEX                    ;else test further
            BNE    doChkBad        ;Bad range
            CMP    #$18            ;Must be <$118 (280)
            BCC    doChkOK
doChkBad    SEC                    ;Set carry for an error
            RTS

doChkOK     CLC
            RTS

LD6EA       DS     2,0             ;Not used

* ---------------------------------------------------------
* Variables for handling mirror devices
* NB. Values of SmartPort unit #s: $00, $01-$7E
* Status List - ref pg 122 IIGS Firmware

spStatList  EQU    *
genStatus   DB     0
spDevTotBlks       DB              0,0,0 ;# of blocks

spUnits     DS     $F,0            ;table of SmartPort unit #s
            DB     0