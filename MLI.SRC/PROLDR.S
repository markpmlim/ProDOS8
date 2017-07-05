            TTL    'ProDOS Kernel Loader'

*---------------------------------------------------------*
*     Disassembled with The Flaming Bird Disassembler     *
*    (c) Phoenix corp. 1992,93  -  All rights reserved    *
*---------------------------------------------------------*
            ORG    $2000
            MX     %11

* There are 3 boot entry points here

NormalBoot  JMP    ProStart        ;Normal boot entry point...
            JMP    NetBootP8       ;Network booted into P8
            JMP    NetBootGSOS     ;Network-booted into GS/OS

*-------------------------------------------------
* Messages

apple2Msg   ASC    "Apple II"
p8VerMsg    ASC    "ProDOS 8 V2.0.3      06-May-93"
blanks      ASC    "            "
cpyRhtMsg   ASC    "Copyright Apple Computer, Inc., 1983-93"
rsvdMsg     ASC    "All Rights Reserved."
endGreetMsg EQU    *
grtLnZ      EQU    blanks-p8VerMsg/2
grtLnZZ     EQU    cpyRhtMsg-blanks/2
grtLnZZZ    EQU    endGreetMsg-rsvdMsg/2

NetBootGSOS INC    SetupRTS        ;Setup and
NetBootP8   INC    SetupRTS        ; RTS entry point...

*-------------------------------------------------
ProStart    LDA    unitNum         ;Get boot device number
            STA    bUnit           ;Save it for later 'prefix'
            JSR    Greet           ;Put up greeting message
            SED
            LDA    #$99            ;Check we have a 65C02
            CLC
            ADC    #$01            ; by using chip's decimal mode
            CLD
            BMI    m48K            ;Error

            LDA    #$01
            TRB    STATEREG
            LDX    #<tablIntrp     ;Move interpreter loader to $800
            LDY    #>tablIntrp
            JSR    Reloc
            BCS    m48K            ;Branch if error

            LDY    #$00
            LDA    #$FF            ;Make sure there is
            STA    $BFFF           ; at least 48K
            EOR    $BFFF
            SEC
            BNE    m48K            ;Branch if not
            STA    $BFFF           ;Try again. Once may have been lucky!
            LDA    $BFFF
            BNE    m48K
            LDA    RDROM2          ;Enable Motherboard ROM
            JSR    WhichROM        ;Get preliminary system configuration
            BCS    m48K            ;Branch if apple /// emulation
            LDA    apple           ;Test for 48K configuration
            AND    #$20            ; by testing for 64K plus
            BNE    m64K            ;Branch if >48k
m48K        JMP    ReqEnh2         ;Must have at least 64K

m64K        LDX    #<tabl64        ;Now move/relocate whatever we got
            LDY    #>tabl64
            JSR    Reloc
            LDA    kVersion        ;Get current revision number
            STA    XDOSver         ; & save it for directory use
NoGood0     BCC    :1
            JMP    NoGood

:1          LDA    RDROM2          ;Enable Motherboard ROM
            LDX    VERSION         ;Look for //e family
            CPX    #$06
            BNE    ItsAIIe
            LDA    #%11100000      ;phylum check on high 2 bits
            BIT    $FBC0           ;Another approved location
            PHP                    ;Save the results from the bit
            LDA    apple
            AND    #%00110111      ;Mask off bits 7,6 and 3
            PLP                    ;Get results back
            BVC    Set3            ;//c or //x
            BMI    Set7            ;Branch if //e

Set3        PHP                    ;Save the results from the bit again
            ORA    #%00001000      ;Set bit 3 on
            PLP
            BPL    Mach2           ;Branch if //c
            ORA    #%01000000
            BPL    SaveMach        ;Always...

Mach2       INC    cFlag-LIcode+LoadIntrp;Make it easy to see if we're on //c later
            BVS    SaveMach
Set7        ORA    #%10000000      ;Set bit 7 on

SaveMach    STA    apple
            LDA    RDROM2          ;Enable ROM for Cortland ID routine
            SEC                    ;Carry will determine if cortland or not
            JSR    IDroutine       ;RTS in all a //'s prior to Cortland
            BCS    ItsAIIe         ;Branch if really a //e
            INC    cortLand        ;Set loader's cortland flag!
            STZ    $04FB           ;Screenhole
            JSR    SetVid

* If SetupRTS is zero, zero out OS_BOOT for AppleTalk.
*  (SetupRTS reflects whether we're ProDOS 8 regular or
*  running with the GSOS.)

            LDA    SetupRTS
            BNE    ItsP8
            STAL   OS_BOOT         ;Flag system was booted w/P8
            JSR    GSPatches       ;Patch GS/OS vectors
ItsP8       EQU    *
ItsAIIe     LDA    bUnit           ;Place boot devnum in globals
            STA    bbUnit
            STA    DevNum
            JSR    DevSrch         ;Finish setting up globals
            LDA    bbUnit
            STA    DevNum
            JSR    LC1In
            LDX    #<TClkStuff     ; & set up clock
            LDY    #>TClkStuff
            JSR    Reloc
NoGood1     BCS    NoGood0         ;Give up any time we got problems

*  Dispatcher 1 must go in bank 2 of language card
*   in a 64K or larger system.

            LDA    #<CallDisp
            STA    jSpare+1        ;Put dispatcher relocator address
            LDA    #>CallDisp      ; into jspare vector
            STA    jSpare+2
            LDA    LCBANK2
            LDA    LCBANK2         ;Switch in bank 2
            LDX    #<DispGS        ;Relocate GS dispatcher
            LDY    #>DispGS
            LDA    SetupRTS
            CMP    #$02            ;GS/OS boot?
            BEQ    RelocDisp       ;Yes

            LDX    #<DispBB        ;Install Better Bye
            LDY    #>DispBB
            LDA    MachID
            BIT    #$00
            BNE    RelocDisp       ;Never!
            AND    #%1100_0010     ;IIe/III emul/IIc
            CMP    #%1000_0010     ;IIe/IIc & 80-col card?
            BEQ    RelocDisp       ;Go install BB dispatcher
            LDX    #<Disp64        ;Install old 40-col dispatcher
            LDY    #>Disp64
            INC    No80Col

RelocDisp   JSR    Reloc
            LDA    #$EE            ;Nonsense byte to distinguish bank 2
            STA    $D000
            JSR    LC1In           ;Switch bank 1 back in
            BCS    NoGood1

* Test for 128K so /RAM disk can be installed

ChkRAM      LDA    MachID
            AND    #$30
            EOR    #$30
            BNE    NoRAMdsk

************ see rev note #45 *************

            LDX    #$FF            ;X used to init Aux SP to $FF
            PHP                    ;Save interrupt status
            PLA                    ; in A-reg
            SEI                    ;No interrupts for safety's sake
            STA    SETALTZP        ;Swap in Aux LC & zp & stack
            STX    $0101           ;Init Aux SP to $FF
            STA    SETSTDZP        ;Back to main LC, zp, and stack
            PHA                    ;Restore
            PLP                    ; interrupt status
            STA    SETINTC3ROM     ;Make sure internal slot 3 ROM is in
            JSR    RAM_1           ;Go install /RAM 

*  Now check for interrupt vector. If vector <$D000 then we
*    have new ROMs and should re-point vector in language card to
*    ROM vector and set a flag byte. If vector is >$D000, reset
*    flag byte and do nothing.

NoRAMdsk    LDA    ROMIN2          ;Switch in ROM
            LDY    IrqVect
            LDX    IrqVect+1       ;Get hi byte of irq vector

* The jsr LC1In was moved here from after the BCS Chk4Card so the
* sta IrqFlag is written to the proper bank.

            JSR    LC1In

*--------------------- see rev note #29 ------------------------

            CPX    #$D0            ;Is it >$D000 (old ROMs)
            LDA    #$00            ;Anticipate not
            BCS    Chk4Card        ;  but branch if they are old ROMs
            STA    SETALTZP        ;Swap Aux LC, zpg and stack
            LDA    #$FF            ;Set Aux stack pointer at $FF
            STA    $0101           ;  while we're here
            STX    IrqVect+1
            STY    IrqVect         ;Save ROM vector in Aux lang. card
            STA    SETSTDZP        ;Swap in main lc, zpg and stack
            STX    IrqVect+1
            STY    IrqVect         ;Save ROM vector in main lang. card
            LDA    #$01            ;Set IrqFlag to show new ROMs
Chk4Card    STA    IrqFlag
            STZ    cortFlag        ;Assume we're not on a cortland
            LDA    cortLand        ;Are we running on a cortland?
            BEQ    NoCort          ;If not branch, and muck w/slot 3!
            INC    cortFlag        ;Make it a one if we're on cortland
            BRA    DoCard

* Check for a ROM in slot 3. Switch in internal
* $C300 firmware if no ROM seen

NoCort      STA    SETINTC3ROM     ;Start with internal firmware switched in
            LDA    SltByt          ;Get slots ROM pattern
            AND    #%00001000      ;Mask off all but slot 3
            BNE    IsROMin3        ;Branch if there is rom in slot three
            BRA    NoSlot3ROM      ;Continue with boot....

* We've seen a ROM in slot 3. Is it an external, identifiable 
*  80-col card with interrupt routines? If so, enable it.
*  If not, switch in the internal $C300 firmware.

IsROMin3    STA    SETSLOTC3ROM    ;Switch in slot 3 ROM
            LDA    $C305           ;1st generic terminal card ID byte
            CMP    #$38
            BNE    HitSwtch        ;Branch if not a terminal card
            LDA    $C307           ;2nd generic terminal card ID byte
            CMP    #$18
            BNE    HitSwtch        ;Branch if not a terminal card
            LDA    $C30B           ;3rd generic terminal card ID byte
            CMP    #$01
            BNE    HitSwtch        ;Branch if not a terminal card
            LDA    $C30C           ;Is it an Apple 80-col card compatible?
            AND    #$F0            ;Mask off lo nibble
            CMP    #$80            ; and check for $8n
            BNE    HitSwtch        ;Branch if not an 80-col card
            LDA    MachID          ;Get the machine ID
            AND    #%11001000
            CMP    #$C0            ;Is it a //+?
            BEQ    DoCard          ;Branch if it is
            LDA    $C3FA           ;Check for interrupt handler routine
            CMP    #$2C            ; in the magic $C3FA spot
            BEQ    DoCard          ;Branch if interrupt handler is there!
HitSwtch    STA    SETINTC3ROM     ;Switch in internal $C300 ROM

* Verify that the card in the aux slot is actually there.

            STA    SET80COL        ;80-store on
            STA    TXTPAGE2
            LDA    #$EE
            STA    $0400
            ASL
            ASL    $0400
            CMP    $0400
            BNE    Maybee          ;Branch if not there
            LSR
            LSR    $0400
            CMP    $0400
Maybee      STA    TXTPAGE1        ;Main memory
            STA    CLR80COL        ;80-store off
            BEQ    DoCard          ;Branch if card is there
            LDA    MachID          ;Get machine id byte
            AND    #%11111101      ;Mask off 80-col bit
            BNE    DoCard1

* OK, the card's good. Leave it enabled and update the MachID

DoCard      LDA    MachID
            ORA    #%00000010
DoCard1     STA    MachID
NoSlot3ROM  LDA    cortLand        ;Are we running on a cortland?
            BEQ    NotCortLand     ;Branch if not
            LDA    #$4C            ;Enable clock routine by
            STA    DateTime        ; putting a JMP in front of clock vector
            LDX    #<cortClock     ;Now set up for relocating
            LDY    #>cortClock     ; the cortland clock driver
            JSR    Reloc           ; and relocate it
            LDA    #$01            ;Denote clock present in MachID byte!
            TSB    MachID          ; bit 0 set to 1
NotCortLand LDA    SetupRTS        ;Get value of setup entry point flag...
            BEQ    NoRTS           ;Branch if normal boot...
            LDA    RDROM2          ;Make sure the ROM is in for consistency...
            RTS                    ;Return to the caller at the setup entry point. ($2003/$2006)

SetupRTS    DB     $00             ;0-Normal Boot, 1-Ret 2-Ret to GS/OS

NoRTS       EQU    *
*************************************************
* Now set prefix to boot device.
* 
            JSR    GoPro           ;First 'online'(was labled bootpfx,#en3)
            DB     $C5
            DA     olParm
            BCS    NoGood          ;Branch if problems
            LDA    pnBuf+1         ;Get volume name length
            AND    #$0F            ;strip devnum
            BEQ    NoGood          ;Branch if error
            INC                    ;Add 1 for leading '/'
            STA    pnBuf           ;Save prefix length
            LDA    #'/'            ;Place leading '/' in path name buf
            STA    pnBuf+1
            JSR    GoPro           ;Set prefix
            DB     $C6
            DA     PfxParm
            BCS    NoGood          ;Branch if problems
            TAX                    ;(A) = 0 after successful MLI call
            STX    dst             ;(Zerored)
            LDY    #$02            ;Read root directory into buffer
            LDA    #>ABuf          ; starting  at $0C00
RdDirBlks   STA    dst+1
            STA    dbBufr+1        ;(using a pointer in zero page also)
            STY    dbBlock
            STX    dbBlock+1
            JSR    GoPro
            DB     $80             ;Block read
            DA     dbParms
            BCS    NoGood

            LDY    #$03            ;Get next block number from link
            LDA    (dst),Y
            TAX
            DEY
            ORA    (dst),Y         ;If both bytes are the same i.e. 0, 0
            BEQ    ExitDirBlkRd    ; then no more blocks of directory
            LDA    (dst),Y
            TAY
            LDA    dst+1
            CLC
            ADC    #$02            ;Add $200 to buffer pointer until
            CMP    #$14            ; it points past $13FF
            BCC    RdDirBlks       ;If ok, read next block
ExitDirBlkRd       JMP             LoadIntrp ;All is well, load interpreter!!!

NoGood      STA    RDROM2          ;Make sure rom is there
            JSR    HOME            ;Clear video
            LDY    #mesLen         ;Print message centered on screen
:loop       LDA    errMess,Y
            STA    SLIN11+4,Y
            DEY
            BPL    :loop
Hang        BMI    Hang

mesLen      EQU    29
errMess     ASC    "Relocation/Configuration Error"

ReqEnh2     LDY    #mes2Len
:loop2      LDA    errMess2,Y      ;Requires enhanced //
            STA    SLIN13+2,Y
            DEY
            BPL    :loop2
Hang2       BMI    Hang2

*-------------------------------------------------
mes2Len     EQU    35
errMess2    ASC    "REQUIRES ENHANCED APPLE IIE OR LATER"

olParm      DB     $02
bUnit       DB     $60             ;Boot Unit
            DA     pnBuf+1

PfxParm     DB     $01
            DA     pnBuf

* Dir block read

dbParms     DB     $03
bbUnit      DB     $00
dbBufr      DA     $0000
dbBlock     DW     $0000

cortLand    DB     $00             ;Non-zero if IIgs
No80Col     DB     $00             ;Flag 40-col dispatcher to be installed

*-------------------------------------------------
AuxGo       EQU    $03F0           ;Entry point to Aux LC driver call routine
cZero       EQU    $00
cMove       EQU    $01
cReloc      EQU    $04
cDone       EQU    $FF
entLen      EQU    $0C23

* Code move tables are explained in file Reloc.s

tablIntrp   DB     cMove           ;Move interpreter loader code & tables
            DA     LoadIntrp       ;Code is address independent
            DW     pcLen
            DA     LIcode

Pg3Tbl      DB     cMove
            DA     AuxGo           ;was $3D6
            DW     $0010           ; and $002A
            DA     pg3Stuff

            DB     cMove
            DA     look            ;dest addr
            DW     $0002           ;# of bytes to move
            DA     dst             ;src addr

            DB     cMove           ;Move 128K test to zero page
            DA     Test128
            DW     End128
            DA     Strt128
            DB     cDone

Disp64      DB     cMove
            DW     $D100           ;lang card bank 2
            DW     $0300           ;3 pages
            DA     SEL_0           ;$5A00
            DB     cDone

DispBB      DB     cMove
            DA     $D100           ;lang card bank 2
            DW     $0300
            DA     SEL_1           ;$5D00
            DB     cDone

DispGS      DB     cMove
            DA     $D100           ;lang card bank 2
            DW     $0300
            DA     SEL_2           ;$6000

            DB     cMove
            DA     DispAdr         ;$1000
            DW     $0300
            DA     SEL_2           ;$6000
            DB     cDone

*-------------------------------------------------
* The following table is for moving the 64K version of
* the MLI to its execution address.

tabl64      DB     cMove           ;Relocate the interrupt/break/reset
            DA     IntHandler      ; handler and associated vectors
            DW     $0065           ;Number of bytes to relocate
            DA     MLI_3           ;Source address of code to relocate

            DB     cMove           ;Move preset 64K version of globals
            DA     Globals
            DW     $0100
            DA     MLI_1

            DB     cZero           ;Clear buffers/workspace
            DA     orig            ;dest
            DW     $0700           ;# of bytes to zero

            DB     cMove           ;Move 64k version of MLI to language card
            DA     orig1           ;See #45..put rwts in lc bnk2 to make MLI_2
            DW     $2100           ;MLI length
            DA     MLI_2

            DB     cMove           ;Move 64K version of
            DA     RWTS            ; Disk ][ routines
            DW     $0700
            DA     XRW_0
            DB     cDone           ;Clock moved later

TClkStuff   DB     cMove           ;Lastly move/relocate thunderclock
            DA     ClockBegin      ; whether needed or not
            DW     $007D
            DW     TCLOCK_0
            DB     cReloc          ;Adjust slot addresses
            DA     ClockBegin
            DW     $0069
            DA     ClockBegin
            DB     $00
clock64     EQU    *+2
            DB     $C1             ;Last changed by DevSrch to correct slot#
            DB     $C1
            DB     $00
            DB     cDone

********** see rev note #50 *********

cortClock   DB     cMove           ;Cortland clock relocating table
            DA     ClockBegin      ;Destination address
            DW     $007D           ;Length of 125 bytes
            DW     CCLOCK_0        ;Source load address of driver
            DB     cDone

****************** see rev note #56 *************
*
* Let's load and jsr to the appletalk configuaration file "atinit"
* if it is found. If it is not found, just continue with the loading
* and running of the ".SYSTEM" file.

LIcode      EQU    *
            JSR    GoPro           ;Make a get file info call to make
            DB     $C4             ; atInit file is there and is
            DA     gfiList         ; of the proper file type
            BCC    GFI_ok          ;Branch if call successful...
            CMP    #fileNotFound   ;Was error "file not found"?
            BEQ    LoadInt
            BNE    ATLoadErr       ;Otherwise fatal i/o error in loading atInit
GFI_ok      LDA    gfiType         ;Now see if atInit file is of proper type...
            CMP    #$E2            ;Is it the correct file type? 
            BNE    ATLoadErr       ;Error if wrong file type!

            JSR    GoPro           ;Open atInit file
            DB     $C8
            DA     atOpen          ; parameter list...
            BNE    ATLoadErr       ; branch if error...
            LDA    #$9F            ;39.75K
            STA    rdLen+1
            STZ    rdLen
            JSR    GoPro
            DB     $CA
            DA     rdParm
            BNE    ATLoadErr
            JSR    GoPro
            DB     $CC
            DA     clParm
            BNE    ATLoadErr
            LDA    RDROM2          ;Put ROM on line for atInit....
            JSR    $2000           ;Call the atInit routine to set up appletalk stuff
LoadInt     JMP    GoLoadInt       ;Go execute the .SYSTEM file

ATLoadErr   LDX    atErr
:1          LDA    atErr,X
            STA    SLIN15,X
            DEX
            BNE    :1
ATerrHang   BEQ    ATerrHang
atErr       STR    "Unable to load ATInit file"

gfiList     EQU    *-LIcode+LoadIntrp
            DB     $0A             ;Parameter count
            DA     atInitName      ;Pointer to "atinit" file name
            DB     $00             ;access
gfiType     EQU    *-LIcode+LoadIntrp
            DB     $00             ;File type
            DS     13,0            ;Space for rest of parameters...

atOpen      EQU    *-LIcode+LoadIntrp
            DB     $03
            DW     atInitName      ;Pointer to "atinit" file name
            DA     $1400           ;Address of I/O buffer
            DB     $01             ;Reference number hard coded since no other files

atInitName  EQU    *-LIcode+LoadIntrp
            STR    "atinit"        ;Name of appletalk config file

GoLoadInt   EQU    *-LIcode+LoadIntrp
            LDA    #>ABuf          ;Search directory already in
            STA    idxl+1          ; memory between $0C00 & $13FF
            LDA    #<ABuf+4        ;Start 1 entry past header
            BNE    AddEntLen       ;Always
NxtEntry    LDA    idxl            ;Calc next entry posn
AddEntLen   CLC
            ADC    entLen          ;Bump to next entry address
            STA    idxl
            BCS    PageCros        ;Branch if page cross
            ADC    entLen          ;Test for end of block
            BCC    NoCros          ;Branch if definitely not page cross
            LDA    idxl+1
            LSR                    ;End of block?
            BCC    NoCros          ;Branch if not
            CMP    #$09            ;End of directory?
            BNE    :1              ;Branch if an interpreter file
            JMP    JustQuit        ;No interpreter file

:1          LDA    #$04            ;Reset index to first entry in next block
            STA    idxl
PageCros    INC    idxl+1          ;Bump to next page
NoCros      LDY    #$10            ;First off, check file type
            LDA    #$FF            ;Must be ProDOS SYS file
            EOR    (idxl),Y
            BNE    NxtEntry        ;Branch if not
            TAY                    ;else check to see if active
            LDA    (idxl),Y        ;(Y)=0 (stortype/namelen)
            BEQ    NxtEntry        ;Branch if deleted file
            AND    #$0F            ;Strip file 'kind'
            STA    pnBuf           ;Save name's length
            CMP    #$08            ;Must be at least 'x.SYSTEM'
            BCC    NxtEntry        ;Otherwise, ignore it

            TAY                    ;Compare last 7 characters for '.SYSTEM'
            LDX    #7-1
LookIntrp   LDA    (idxl),Y
            EOR    iterP,X
            ASL
            BNE    NxtEntry        ;Branch if something else
            DEY
            DEX
            BPL    LookIntrp

            LDY    #$00            ;Move name to pathname buffer
MovIntrp    INY
            LDA    (idxl),Y
            STA    pnBuf,Y
            ORA    #$80            ;Make it printable in case of error
            STA    ioMess+$11,Y
            CPY    pnBuf           ;All characters moved?
            BNE    MovIntrp        ;Nope

            LDA    #" "            ;Save a space after name
            STA    ioMess+$12,Y
            TYA                    ;Update error message length
            ADC    #$13            ;(carry was set)
            STA    ioErrLen
            JSR    GoPro           ;Open interpreter file
            DB     $C8
            DA     opParm
            BNE    BadLoad
            JSR    GoPro           ;Get file's length
            DB     $D1
            DA     efParm
            BNE    BadLoad

            LDA    eof+2           ;Make sure file will fit
            BNE    TooLong
            LDA    eof+1
            CMP    #$9F            ;Max size is 39.75K
            BCS    TooLong
            STA    rdLen+1
            LDA    eof             ;Read entire file
            STA    rdLen
            JSR    GoPro
            DB     $CA
            DA     rdParm
            BEQ    GoClos          ;Branch if successful read
            CMP    #badBufErr      ;Memory conflict?
            BEQ    TooLong
            BNE    BadLoad         ;Report i/o error
GoClos      JSR    GoPro
            DB     $CC
            DA     clParm
            BNE    BadLoad         ;(branch never, we hope)

***************************************************
* If we are booting on a //c and an escape is in the keyboard buffer
*  then clear it so we dont interfere with start application
*  (pizza accelerator chip requires ESC to shift speed down)

            LDA    cFlag-LIcode+LoadIntrp;Booting on a 2c?
            BEQ    Going           ;Branch if not
            LDA    KBD             ;Fetch last key in board (pending or not)
            CMP    #$9B            ;ESCAPE character? (with bit 7 on)
            BNE    Going           ;Branch if not
            STA    KBDSTROBE       ;Clear keyboard strobe

Going       LDA    RDROM2          ;Enable Motherboard ROM
            JMP    $2000           ;GoInterP

cFlag       DB     $00             ;=1 if an apple 2c

*-------------------------------------------------
* Transfer control to the dispatch/selector

JustQuit    EQU    *-LIcode+LoadIntrp
            JSR    GoPro
            DB     $65
            DW     quitParm

BadLoad     LDY    ioErrLen        ;Center the bad news
            LDA    #$27            ;Report no interpreter
            SEC
            SBC    ioErrLen
            LSR
            ADC    ioErrLen
            TAX
:NoItrp     LDA    ioMess,Y
            STA    SLIN15,X
            DEX
            DEY
            BPL    :NoItrp
            BMI    Hang10

TooLong     LDY    #$1E
:loop       LDA    lgMess,Y
            STA    SLIN15+5,Y
            DEY
            BPL    :loop
Hang10      BMI    Hang10

*-------------------------------------------------
lgMess      EQU    *-LIcode+LoadIntrp
            ASC    "**  System program too large  **"
ioMess      EQU    *-LIcode+LoadIntrp
            ASC    "** Unable to load X.System *********"
ioErrLen    EQU    *-LIcode+LoadIntrp
            DB     $00

opParm      EQU    *-LIcode+LoadIntrp
            DB     $03
            DA     pnBuf           ;pathname
            DA     $1400
            DB     $01

efParm      EQU    *-LIcode+LoadIntrp
            DB     $02
            DB     $01
eof         EQU    efParm+2
            HEX    000000

rdParm      EQU    *-LIcode+LoadIntrp
            DB     $04
            DB     $01
            DA     $2000
rdLen       EQU    rdParm+4
            DW     $0000
            DW     $0000

clParm      EQU    *-LIcode+LoadIntrp
            DB     $01
            DB     $00

quitParm    EQU    *-LIcode+LoadIntrp
            DB     $04
            DB     $00             ;=$EE for enhanced quit
            DW     $0000           ;addr of pathname
            DB     $00             ;reserved
            DW     $0000           ;reserved

iterP       EQU    *-LIcode+LoadIntrp
            ASC    ".SYSTEM"
pcLen       EQU    *-LIcode

pg3Stuff    EQU    *               ;This stuff goes on page 3
* ------------------- see rev note 15 --------------------------
*
* Locate between vectors in page 3 starting at $3F0
*
*  Note: since this is treated as a subroutine from the MLI,
*        nothing may use the stack in main ram area!!
*
*  x = 5 from calling routine to move parameter bytes in the call

            DW     $FA59           ;mon_Break
            DW     $FF59           ;mon_Reset
            DB     $5A             ;Powerup byte
            JMP    OLDRST          ;'&' vector
            JMP    OLDRST          ;mon_ctrl-Y vector
            DB     $00,$40,$00     ;mon_nmi
            DA     IrqEnt          ;Interrupt vector to global page

LC1In       LDA    LCBANK1         ;Swap LC bank1 in
            LDA    LCBANK1
            RTS

*-------------------------------------------------
WhichROM    STZ    apple           ;Assume standard apple ][ first
            LDX    VERSION         ;Look at the approved location...
            CPX    #$38            ;Apple ][? (actually is it autostart ROM?)
            BEQ    TestLCRAM       ;Yes
            LDA    #$80            ;else try for apple //e
            CPX    #$06
            BEQ    MuchRAM         ;Yes, //e
            LDA    #$40            ;If that fails, try ][+
            CPX    #$EA            ;Must be one of these values...
            BNE    WhatsIt
            LDX    $FB1E           ;If it passes as ][+, then
            CPX    #$AD            ; it might be /// in emulation
            BEQ    MuchRAM
            LDA    #$D0            ;Mark it as 48k /// emulation!
            CPX    #$8A            ; if it passes the test
            BNE    WhatsIt         ;Branch always, well, maybe
NSMach      SEC                    ;48K not allowed so apple ///
            RTS                    ; emulation is not sufficient memory

WhatsIt     LDA    #$02            ;Machine unknown if we land here
            STA    (dst),Y
            BNE    FindRAM         ;branch always

MuchRAM     STA    apple           ;Save ROM id
TestLCRAM   JSR    LC1In           ;Test for the presence of
            LDA    #$AA            ; 'language' card RAM
            STA    $D000
            EOR    $D000           ;If it is there, result is zero
            BNE    NSMach          ;Branch if it is not
            LSR    $D000           ;else check twice just to be sure
            LDA    #$55
            EOR    $D000
            BNE    NSMach          ;Non-standard machine
            LDA    #$20            ;Indicate at LC RAM available
            ORA    apple
FindRAM     JMP    Test128         ;Go test for 128K

*-------------------------------------------------
* The code below is moved to $80 before execution

Test128     EQU    $80             ;Use zpage for this routine
Strt128     STA    apple           ;Save accumulated value
            BPL    Not128          ;Branch if sure it's less than 128K
            LDA    #$EE            ;First try storing in Aux Mem
            STA    WRCARDRAM       ;Write to aux while on main ZPage
            STA    RDCARDRAM       ;Set to read aux ram
            STA    $0C00           ;Check for sparse mem mapping
            STA    $0800
            LDA    $0C00           ;See if sparse memory -same value
            CMP    #$EE            ; 1K away
            BNE    NoAux
            ASL    $0C00           ;May be sparse mem so change value
            ASL                    ; & see what happens
            CMP    $0C00
            BNE    NoAux
            CMP    $0800
            BNE    AuxMem
NoAux       SEC                    ;Sparse mapping so no aux mem
            BCS    Back2Main
AuxMem      CLC                    ;There is aux mem
Back2Main   STA    WRMAINRAM       ;Switch  back to write main ram
            STA    RDMAINRAM       ;Switch back main ram read
            BCS    Not128          ;Branch if not 128K
            LDA    apple           ;else update identity of machine
            ORA    #$30            ;Indicate 128K present
            STA    apple
Not128      LDA    look+1          ;Futs with pointer for apple test
            SEC
            SBC    #$05            ;Should result in $FB if zpage is ok
            STA    look+1
            BCS    *+4             ;(to the CLC)
            DEC    look
            CLC
            RTS
End128      EQU    *-Strt128       ;Byte count for routine move to zpage
