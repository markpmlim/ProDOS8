            TTL    'xdos R/W routines revised'
****************************************************
*
*          PRODOS 8 DISK II DRIVER (RWTS)
*
*         COPYRIGHT APPLE COMPUTER INC., 1980-1986
*
*             ALL RIGHTS RESERVED
*
*          REVISED 11/8/82 BY J.R.H.
*
****************************************************
****************************
*                         *
*     critical timing     *
*   requires page bound   *
*   considerations for    *
*      code and data      *
*     code-----      *
*   virtually the entire  *
*     'write' routine     *
*      must not cross     *
*     page boundaries.    *
*  critical branches in   *
*  the 'write', 'read',   *
*  and 'read adr' subrs   *
*  which must not cross   *
*  page boundaries are    *
*  noted in comments.     *
*                         *
****************************
*                         *
*         Equates         *
*                         *
maxCmd      EQU    4               ;Commands 0-3 only
dvMot       EQU    $E8
            DUM    $3A
wTemp       DS     1
midNib1     DS     1
midNib2     DS     1
lstNib      DS     1
slotZ       DS     1
yEnd        DS     1
            DEND

************************
*                      *
*    device address    *
*     assignments      *
*                      *
************************
phaseOff    EQU    $C080           ;stepper phase off.
*phaseOn EQU $C081 ;stepper phase on.
q6l         EQU    $C08C           ;q7l,q6l=read
q6h         EQU    $C08D           ;q7l,q6h=sense wprot
q7l         EQU    $C08E           ;q7h,q6l=write
q7h         EQU    $C08F           ;q7h,q6h=write store
****************************************
*
* Equates for rwts and block
*
****************************************
motorOff    EQU    $C088
motorOn     EQU    $C089
drv0En      EQU    $C08A
*drv1en EQU $C08B

            ORG    $D000
************************
*                      *
*       block i/o      *
*                      *
************************
BlockIO     CLD                    ;This must be first as it is an ID value
            JSR    ResetPhase

* this is patch 76 part 1.  part 2 is in xrw2.
* this is patch 77, use to be 'lda q7l+14,x'.

            LDA    q7l,X           ;Turn off write enable please!!!
* (pad is just spare bytes but the number is critical for page
            NOP
            NOP
            JSR    doCheck
            BCS    BadBlk          ;Branch if block # is out of range
            LDY    #$05
:loop       ASL
            ROL    ibTrk
            DEY
            BNE    :loop
            ASL
            BCC    :1
            ORA    #$10            ;Adjust for upper 4 blks of trk
:1          LSR
            LSR
            LSR
            LSR
            PHA                    ;Save sector#
            JSR    RegRWTS
            PLA                    ;Restore sector #
            BCS    Quit            ;Branch if error encountered
            INC    bufPtr+1
            ADC    #$02
            JSR    RegRWTS         ;Get second half of block
            DEC    bufPtr+1
Quit        LDA    ibStat
            RTS

BadBlk      LDA    #drvrIOError
            SEC
            RTS
**************************
*                        *
*     read/write a       *
*   track and sector     *
*                        *
**************************
RegRWTS     LDY    #$01            ;Retry count
            STY    seekCnt         ;Only one recalibrate per call
            STA    ibSect
            LDA    unitNum         ;Get slot # for this operation
            AND    #$70
            STA    slotZ
            JSR    ChkPrev         ;Make sure other drives in other slots are stopped
*
* Now check if the motor is on, then start it
*
            JSR    ChkDrv          ;Set zero flag if motor stopped
            PHP                    ;Save test results
            LDA    #dvMot
            STA    monTimeH
            LDA    unitNum         ;Determine drive one or two
            CMP    iobPrevDn       ;Same drive used before?
            STA    iobPrevDn       ;Save it for next time
            PHP                    ;Keep results of compare
            ASL                    ;Get drive number into carry
            LDA    motorOn,X       ;Turn on the drive
            BCC    DrvSel          ;Branch if drive 1 selected
            INX                    ;Select drive 2
DrvSel      LDA    drv0En,X
            PLP                    ;Was it same drive?
            BEQ    :1              ;Yes
            PLP                    ;Must indicate drive off by setting zero flag
            LDY    #$07            ;Delay 150 ms before stepping
:WaitLoop   JSR    msWait          ;(on return A=0)
            DEY
            BNE    :WaitLoop
            PHP                    ;Now zero flag set
:1          LDA    dhpCmd          ;Make sure this command needs seeking
            BEQ    :2              ;Branch if status check
            LDA    ibTrk           ;Get destination track
            JSR    MySeek          ; & go to it

* Now at the desired track. Was the motor
* on to start with?

:2          PLP                    ;Was motor on?
            BNE    TryTrk          ;If so, don't delay, get it today!

* Motor was off, wait for it to speed up.

MotOff      LDA    #$01            ;Wait exactly 100 us for each count in monTime
            JSR    msWait
            LDA    monTimeH
            BMI    MotOff          ;count up to 0000
****************************************
*
* Motor should be up to speed.
* If it still looks stopped then
* the drive is not present.
*
****************************************
            JSR    ChkDrv          ;Is drive present?
            BEQ    HndlErr         ;Branch if no drive

* Now check: if it is not the format disk command,
*  locate the correct sector for this operation.

TryTrk      LDA    dhpCmd          ;Get command code #
            BEQ    StatCmd         ;If $00, then status command
            LSR                    ;Set carry=1 for read, 0 for write
            BCS    :1              ;Must prenibblize for write
            JSR    PreNibl16
:1          LDY    #$40            ;Only 64 retries of any kind
            STY    retryCnt
TryAdr      LDX    slotZ           ;Get slot num into X-reg
            JSR    RdAdr16         ;Read next address field
            BCC    RdRight         ;If read it right, hurrah!
TryAdr2     DEC    retryCnt        ;Another mistake!!
            BPL    TryAdr          ;Well, let it go this time...
            LDA    #drvrIOError    ;Anticipate a bad drive error
            DEC    seekCnt         ;Only recalibrate once!
            BNE    HndlErr         ;Tried to recalibrate a second time, error!
            LDA    curTrk          ;Save track we really want
            PHA
            ASL
            ADC    #$10            ;Pretend track is 8>curtrk
            LDY    #$40
            STY    retryCnt        ;Reset retries to 64 max
            BNE    ReCal1          ;Branch always

* Have now read an address field correctly.
* Make sure this is the desired track, sector, and volume.

RdRight     LDY    track           ;On the right track?
            CPY    curTrk
            BEQ    RtTrk           ;if so, good

* Recalibrating from this track

            LDA    curTrk          ;Preserve destination track
            PHA
            TYA
            ASL                    ;(washing machine fix!)
ReCal1      JSR    SetTrk
            PLA
            JSR    MySeek
            BCC    TryAdr          ;Go ahead and recalibrate

* Drive is on right track, check volume mismatch

RtTrk       LDA    sector          ;Check if this is the right sector
            CMP    ibSect
            BNE    TryAdr2         ;No, try another sector
            LDA    dhpCmd          ;read or write?
            LSR                    ;The carry will tell
            BCC    WriteIt         ;Carry was set for read operation,
            JSR    Read16          ; cleared for write
            BCS    TryAdr2         ;Carry set upon return if bad read
AllDone     EQU    *               ;Was CLC
            LDA    #$00            ;No error
            DB     $D0             ;Branch never (skip 1 byte)
HndlErr     SEC                    ;Indicate an error
            STA    ibStat          ;Give him error #
            LDX    slotZ           ;Get the slot offset
            LDA    motorOff,X      ;Turn it off...
            RTS                    ;All finished!

WriteIt     JSR    Write16         ;Write nybbles now
StatDone    BCC    AllDone         ;If no errors
            LDA    #drvrWrtProt    ;Disk is write protected!!
            BNE    HndlErr         ;Branch always

StatCmd     LDX    slotZ
            LDA    q6h,X           ;Test for write protected
            LDA    q7l,X
            ROL                    ;Write protect-->carry-->bit-0=1
            LDA    q6l,X           ;Keep in read mode...
            JMP    StatDone        ;Branch always taken

* This is the 'seek' routine
*  seeks track 'n' in slot #x/$10
* If drivno is negative, on drive 0
* If drivno is positive, on drive 1

MySeek      ASL                    ;Assume two phase stepper
            STA    track           ;Save destination track(*2)
            JSR    AllOff          ;Turn all phases off to be sure
            JSR    DrvIndx         ;Get index to previous track for current drive
            LDA    drv0Trk,X
            STA    curTrk          ;This is where i am
            LDA    track           ; & where i'm going to
            STA    drv0Trk,X
            JSR    Seek            ;Go there!
AllOff      LDY    #$03            ;Turn off all phases before returning
NxtOff      TYA                    ;(send phase in Acc)
            JSR    ClrPhase        ;Carry is clear, phases should be turned off
            DEY
            BPL    NxtOff
            LSR    curTrk          ;Divide back down
            CLC
            RTS                    ;All off... now it's dark
**************************
*                        *
*  fast seek subroutine  *
**************************
*                        *
*    on entry ----   *
*                        *
*  x-reg holds slotnum   *
*         times $10.     *
*                        *
*  a-reg holds desired   *
*         halftrack.     *
*         (single phase) *
*                        *
*  curtrk holds current  *
*          halftrack.    *
*                        *
*    on exit -----   *
*                        *
*  a-reg uncertain.      *
*  y-reg uncertain.      *
*  x-reg undisturbed.    *
*                        *
*  curtrk and trkn hold  *
*      final halftrack.  *
*                        *
*  prior holds prior     *
*    halftrack if seek   *
*    was required.       *
*                        *
*  montimel and montimeh *
*    are incremented by  *
*    the number of       *
*    100 usec quantums   *
*    required by seek    *
*    for motor on time   *
*    overlap.            *
*                        *
* --- variables used --- *
*                        *
*  curtrk, trkn, count,  *
*    prior, slottemp     *
*    montimel, montimeh  *
*                        *
**************************

Seek        STA    trkNbr          ;Save target track
            CMP    curTrk          ;On desired track?
            BEQ    SetPhase        ;Yes,energize phase and return
            LDA    #$00
            STA    trkCnt          ;Halftrack count
SeekLoop    LDA    curTrk          ;Save curTrk for
            STA    prior           ; delayed turnoff
            SEC
            SBC    trkNbr          ;delta-tracks
            BEQ    SeekEnd         ;branch if curTrk=destination
            BCS    Out             ;(move out, not in)
            EOR    #$FF            ;Calc trks to go
            INC    curTrk          ;Incr current track (in)
            BCC    MinTst          ;(always taken)
Out         ADC    #$FE            ;Calc trks to go
            DEC    curTrk          ;Decr current track (out)
MinTst      CMP    trkCnt
            BCC    MaxTst          ; & 'trks moved'
            LDA    trkCnt
MaxTst      CMP    #$09
            BCS    Step2           ;If trkcnt>$8 leave y alone (y=$8)
            TAY                    ;else set acceleration index in y
            SEC
Step2       JSR    SetPhase
            LDA    OnTable,Y       ;For 'ontime'
            JSR    msWait          ;(100 usec intervals)
            LDA    prior
            CLC                    ;For phaseoff
            JSR    ClrPhase        ;Turn off prior phase
            LDA    OffTable,Y
            JSR    msWait
            INC    trkCnt          ;'tracks moved' count
            BNE    SeekLoop        ;(always taken)
SeekEnd     JSR    msWait          ;Settle 25 msec
            CLC                    ;Set for phase off
SetPhase    LDA    curTrk          ;Get current track
ClrPhase    AND    #$03            ;Mask for 1 of 4 phases
            ROL                    ;Double for phaseon/off index
            ORA    slotZ
            TAX
            LDA    phaseOff,X      ;Turn on/off one phase
            LDX    slotZ           ;Restore x-reg
            RTS                    ; & return
**************************
*                        *
*     7-bit to 6-bit     *
*    'deniblize' tabl    *
*   (16-sector format)   *
*                        *
*      valid codes       *
*    $96 to $ff only.    *
*                        *
*  codes with more than  *
*  one pair of adjacent  *
*   zeroes or with no    *
*  adjacent ones (except *
*   bit 7) are excluded. *
*                        *
*                        *
*  nibls in the ranges   *
*  of $a0-$a3, $c0-$c7,  *
*  $e0-$e3 are used for  *
*  other tables since no *
*  valid nibls are in    *
*  these ranges.         *
**************************

dNibble     EQU    *-$96
            HEX    0004
            HEX    FFFF080C
            HEX    FF101418
TwoBit3     HEX    008040C0        ;Used in fast prenib as
            HEX    FFFF1C20        ; lookup for 2-bit quantities
            HEX    FFFFFF24
            HEX    282C3034
            HEX    FFFF383C
            HEX    4044484C
            HEX    FF505458
            HEX    5C606468
TwoBit2     HEX    00201030        ;Used in fast prenib
EndMarks    HEX    DEAAEBFF        ;Table using 'unused'
            HEX    FFFFFF6C        ; nibls ($c4,$c5,$c6,$c7)
            HEX    FF707478
            HEX    FFFFFF7C
            HEX    FFFF8084
            HEX    FF888C90
            HEX    94989CA0
TwoBit1     HEX    0008040C        ;Used in fast prenib
            HEX    FFA4A8AC
            HEX    FFB0B4B8
            HEX    BCC0C4C8
            HEX    FFFFCCD0
            HEX    D4D8DCE0
            HEX    FFE4E8EC
            HEX    F0F4F8FC
*   page align the following tables.
***************************
*                         *
*     6-bit to 2-bit      *
*   conversion tables.    *
*                         *
* dnibl2 abcdef-->0000fe  *
* dnibl3 abcdef-->0000dc  *
* dnibl4 abcdef-->0000ba  *
*                         *
***************************
*                         *
*     6-bit to 7-bit      *
*  nibl conversion table  *
*                         *
*   codes with more than  *
*   one pair of adjacent  *
*    zeroes or with no    *
*   adjacent ones (except *
*     b7) are excluded.   *
*                         *
***************************

dNibble2    DB     $00
dNibble3    DB     $00
dNibble4    DB     $00
Nibbles     HEX    9602000097
            HEX    0100009A0300009B
            HEX    0002009D0202009E
            HEX    0102009F030200A6
            HEX    000100A7020100AB
            HEX    010100AC030100AD
            HEX    000300AE020300AF
            HEX    010300B2030300B3
            HEX    000002B4020002B5
            HEX    010002B6030002B7
            HEX    000202B9020202BA
            HEX    010202BB030202BC
            HEX    000102BD020102BE
            HEX    010102BF030102CB
            HEX    000302CD020302CE
            HEX    010302CF030302D3
            HEX    000001D6020001D7
            HEX    010001D9030001DA
            HEX    000201DB020201DC
            HEX    010201DD030201DE
            HEX    000101DF020101E5
            HEX    010101E6030101E7
            HEX    000301E9020301EA
            HEX    010301EB030301EC
            HEX    000003ED020003EE
            HEX    010003EF030003F2
            HEX    000203F3020203F4
            HEX    010203F5030203F6
            HEX    000103F7020103F9
            HEX    010103FA030103FB
            HEX    000303FC020303FD
            HEX    010303FE030303FF

nBuf2       DS     $56,0           ;nibble buffer for R/W of low 2-bits of each byte

ibTrk       DB     $00
ibSect      DB     $00
ibStat      DB     $00
iobPrevDn   DB     $00
curTrk      DB     $00
drv0Trk     EQU    *-2
            HEX    00000000000000  ;for slots 1 thru 7
            HEX    00000000000000  ;drives 1 & 2
retryCnt    DS     1,0
seekCnt     DS     1,0
************************
*                      *
*      readadr----     *
*                      *
************************
count       EQU    *               ;'must find' count
last        DS     1,0             ;'odd bit' nibls
chkSum      DS     1,0             ;Used for address header cksum
csSTV       DS     4,0
*       checksum, sector, track, and volume.
sector      EQU    csSTV+1
track       EQU    csSTV+2
volume      EQU    csSTV+3

trkCnt      EQU    count           ;Halftracks moved count
prior       DS     1,0
trkNbr      DS     1,0
************************
*                      *
*    mswait ----   *
*                      *
************************
monTimeL    equ    csSTV+2         ;Motor-on time
monTimeH    equ    monTimeL+1      ;counters.
**************************
*                        *
*  phase on-, off-time   *
*   tables in 100-usec   *
*   intervals. (seek)    *
*                        *
**************************
OnTable     HEX    013028
            HEX    24201E
            HEX    1D1C1C
OffTable    HEX    702C26
            HEX    221F1E
            HEX    1D1C1C

**************************
*                        *
*   mswait subroutine    *
*                        *
**************************
*                        *
*  delays a specified    *
*   number of 100 usec   *
*   intervals for motor  *
*   on timing.           *
*                        *
*    on entry ----   *
*                        *
*  a-reg: holds number   *
*        of 100 usec     *
*        intervals to    *
*        delay.          *
*                        *
*    on exit -----   *
*                        *
*  a-reg: holds $00.     *
*  x-reg: holds $00.     *
*  y-reg: unchanged.     *
*  carry: set.           *
*                        *
*  montimel, montimeh    *
*   are incremented once *
*   per 100 usec interval*
*   for moton on timing. *
*                        *
*    assumes ----    *
*                        *
*   1 usec cycle time    *
*                        *
**************************
msWait      LDX    #$11
:loop       DEX                    ;Delay 86 usec
            BNE    :loop
            INC    monTimeL
            BNE    :1              ;double-byte
            INC    monTimeH        ; increment
:1          SEC
            SBC    #$01            ;Done 'n' intervals?
            BNE    msWait          ;(A-reg counts)
            RTS
