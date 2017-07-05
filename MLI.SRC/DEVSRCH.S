***********************************************************
Greet       LDA    SPKR            ;Give a 'click'
            STA    CLR80VID        ;Disable 80 columns (rev-e)
            STA    CLR80COL        ;Disable '80store'
            JSR    SetNorm
            JSR    Init
            JSR    SetVid
            JSR    SetKBD
            CLD

* Note: interrupts are not turn off
            
            JSR    HOME            ;Clear screen
            LDX    #p8VerMsg-apple2Msg-1;Move greeting to screen
:loop1      LDA    apple2Msg,X     ;"apple ii"
            STA    SLIN09+20-4,X   ;$4A8 starts the line
            DEX
            BPL    :loop1

            LDX    #blanks-p8VerMsg-1
:loop2      LDA    p8VerMsg,X      ;"prodos (version)   (date)"
            STA    SLIN11+20-grtLnZ,X
            DEX
            BPL    :loop2

            LDX    #cpyRhtMsg-blanks-1
:loop3      LDA    blanks,X        ;(blank line)
            STA    SLIN13+20-grtLnZZ,X
            DEX
            BPL    :loop3

            LDX    #rsvdMsg-cpyRhtMsg-1
:loop4      LDA    cpyRhtMsg,X     ;Copyright Message
            STA    SLIN22,X
            DEX
            BPL    :loop4

            LDX    #endGreetMsg-rsvdMsg-1
:loop5      LDA    rsvdMsg,X       ;Rights message
            STA    SLIN23+20-grtLnZZZ,X
            DEX
            BPL    :loop5

            SEC
            JSR    IDroutine
            BCS    NotIIgs         ;Not IIgs
            LDA    #$80
            TRB    NEWVIDEO        ;Enable SuperHires
NotIIgs     LDA    SPKR
            RTS
***************************************************
*
* This routine finds all disk devices plugged into the
*  system's slots that follow apple's disk id convention.
*  The routine sets up the address and device table in
*  ProDOS's system global page.  13-sector disk ]['s are 
*  not configured since they may not function properly in
*  the 16 sector mode...
*
* Profiles, and other intelligent devices, are expected to
*  have ROMs containing the disk I/O drivers.
*
* This routine was revved 8/21/86 to make sure that correct number
*  of smartport devices are installed, and that disk ][s are always
*  searched last by placing them at the end of the list.  Disk ][ unit
*  numbers are stacked at the end of the device table, while regular
*  devices are stacked at the beginning.  After all slots have been
*  searched the two lists are combined. see note 60.
*
statusList  EQU    *
spDevStatus EQU    *
numDevices  DS     8,0             ;Eight bytes for smartport call

maxUnitP1   EQU    *               ;# of units connected to SP+1
driverAdr   DA     $0000
dsk2Idx     DB     $00
diskInSlot2 DB     $00             ;msb set if drive in slot 2

*-------------------------------------------------
DevSrch     STZ    dst
            STZ    dst+1
            STZ    indrcn          ;Set up for search
            LDX    #$FF
            STX    DevCnt          ;Device count=none
            LDA    #14             ;Start disk ][ area at the end of devlist
            STA    dsk2Idx
*********************** see note #65 ***********************
*
* Make a quick check of slot 2. If there is a disk card there,
*  clear the msb of diskInSlot2. This will limit the number of
*  devices in any slot 5 smartport card to 2.
*
            LDA    #$C2
            STA    indrcn+1        ;Check slot 2
            JSR    CmpID           ;Is there a disk card in slot 2?
            ROR    diskInSlot2     ;Clear msb if so, set otherwise
            LDA    #$C7            ;Search slots from high to low
            STA    indrcn+1
FindDsk     EQU    *

***************** code here became a subroutine ****************
************************* see note #65 *************************

            JSR    CmpID
            BCS    NxtDsk          ;Carry set means no card this slot
            LDA    (indrcn),Y      ;Check last byte of $Cn ROM
            BEQ    DiskII          ;If =00 then 16 sector disk ][
            CMP    #$FF            ;If =ff then 13 sector disk ][
            BCS    NxtDsk          ;Ignore if 13 sector boot ROM
            STA    driverAdr       ;else, assume it's an intelligent disk for now.

            LDY    #$07            ;Check for a SmartPort device
            LDA    (indrcn),Y
            BNE    NoSPort
            JMP    SmartPort

* Ref ProDOS Tech Ref (ROM Code conventions)

NoSPort     LDY    #$FE            ;Get attributes byte & verify it
            LDA    (indrcn),Y
            AND    #$03            ; provides read, write, and status calls
            CMP    #$03            ; (should be #$07)
            SEC                    ;Assume it is a bozo brand disk...
            BNE    NxtDsk
            JSR    SetDevID
            CLC
            PHP                    ;Remember that it's not a disk ][
            LSR                    ;Move # of units (0=1, 1=2) to carry
            LDA    indrcn+1        ;(driverAdr)=low entry addr, save hi addr
            BNE    ADevice         ;Always

DiskII      STA    devID           ;Disk ]['s have null attributes
            SEC
            PHP                    ;Remember it's a disk ][
            LDA    D2BlkIO
            STA    driverAdr
            LDA    D2BlkIO+1

* The carry is already set telling InstallDev
*  to install two devices for disk ][s.

ADevice     STA    driverAdr+1
            JSR    InstallDev      ;Install one or two devices this slot
            PLP                    ;Get back if it's disk ][
            BCC    NoDisk2
            DEX                    ;Move the list pointer back
            DEX                    ;(installdev left X set)
            STX    DevCnt
            DEC    dsk2Idx         ;Increase the disk ][ index
            DEC    dsk2Idx
            LDY    dsk2Idx
            INX                    ;Increase X in case =$FF
            LDA    DevLst+1,X
            STA    DevLst,Y
            LDA    DevLst,X
            STA    DevLst+1,Y
            DEX                    ;Back to DevCnt again

NoDisk2     EQU    *
NxtDsk2     CLC
NxtDsk      JSR    SlotROM         ;Test for clock & other devices
            DEC    indrcn+1        ;Set up for next lower slot
            LDA    indrcn+1        ;Have all slots been checked?
            AND    #$07
            BNE    FindDsk         ;No

            JSR    ScanAll4SP      ;Mirror smartport devices

* Now copy the disk ][ list to the end of the regular list
*  start by making the device count include disk ][s

            LDX    DevCnt          ;Load up current devcnt-1
            LDA    #14
            SEC
            SBC    dsk2Idx
            BEQ    D2Snone         ;If there were no disk ][s, forget it
            CLC
            ADC    DevCnt          ;Sum of disk ][s and others
            STA    DevCnt
            INX                    ;Move to open space in regular list

            LDY    #13             ;First disk ][ entry
MLab        LDA    DevLst,Y
            PHA
            LDA    DevLst,X
            STA    DevLst,Y
            PLA
            STA    DevLst,X
            INX
            DEY
            STY    dsk2Idx         ;Use as a temp
            CPX    dsk2Idx
            BCC    MLab            ;Continue 'til indices cross...

D2Snone     LDY    #$00
            LDX    DevCnt          ;Now change the device order
:loop       LDA    DevLst,X        ; so that the boot device
            PHA
            AND    #$7F
            EOR    DevNum          ; will have highest priority
            ASL
            BNE    :1
            PLA
            INY
:1          DEX
            BPL    :loop

            LDX    DevCnt          ;Now reverse order of search, hi to lo
            TYA                    ;Was boot device found?
            BEQ    :2              ;No
            LDA    DevNum          ;Make boot device first in search order
            STA    DevLst,X
            DEX
            BMI    DevSrchEnd      ;Branch if only one device
            DEY                    ;Is this a 2-drive device?
            BEQ    :2              ;No
            EOR    #$80            ;Make boot device, drive 2 next
            STA    DevLst,X
            DEX
            BMI    DevSrchEnd      ;Branch if only one device, 2 drives
:2          PLA
            STA    DevLst,X
            DEX
            BPL    :2

DevSrchEnd  JSR    Fndtrd          ;Save accumuated machine ID
            BEQ    WhosIt
            STA    MachID
            RTS
WhosIt      JMP    WhatsIt

staDrv      ORA    devID           ;Combine with attributes (0SSS IIII)
            LDX    DevCnt
            INX                    ;Put device number into device list
            STA    DevLst,X
            ASL                    ;Now form drive 2 device number, if any (SSSI III0)
            RTS

SlotROM     BCC    IsROM           ;Branch if disk drive
            LDY    #$06            ;Test this slot for clock card
:1          LDA    (indrcn),Y
            CMP    clkID,Y         ;Branch if not clock
            BNE    NotClk
            DEY
            DEY
            BPL    :1

            LDA    indrcn+1        ;transfer high slot addr minus $c1 (default)
            SBC    #$C1            ; to relocate references to clock ROM
            STA    clock64
            LDA    #$4C            ;Also enable jump vector in globals
            STA    DateTime
            LDA    apple           ;Mark clock as present
            BEQ    DevSrchEnd
            ORA    #$01
            STA    apple
            BNE    IsROM           ;Always

NotClk      LDY    #$05            ;Test for 80-col card
            LDA    (indrcn),Y      ;One byte at a time
            CMP    #$38
            BNE    NotCons
            LDY    #$07            ;Test values are same as Pascal's
            LDA    (indrcn),Y
            CMP    #$18
            BNE    NotCons
            LDY    #$0B
            LDA    (indrcn),Y
            DEC
            BNE    NotCons
            INY
            LDA    (indrcn),Y
            AND    #$F0            ;Mask off low nibble
            CMP    #$80            ;Generic for 80-col card
            BNE    NotCons
            LDA    apple
            BEQ    DevSrchEnd
            ORA    #$02
            STA    apple           ;Mark config for 80 col. present
            BNE    IsROM
NotCons     LDX    #$00            ;Test for any ROM
            LDA    (indrcn)
            CMP    #$FF            ;Test for apple /// non slot
            BEQ    NoROM           ;Branch if invalid ROM

TestROM     CMP    (indrcn)        ;Look for floating bus
            BNE    NoROM
            INX                    ;Loop 256 times
            BNE    TestROM

IsROM       LDA    indrcn+1        ;Mark a bit in slot byte
            AND    #$07            ; to indicate rom present
            TAX
            LDA    SltBit,X
            ORA    SltByt
            STA    SltByt
NoROM       RTS

*-------------------------------------------------
D2BlkIO     DA     RWTS            ;Addr of Disk ][ driver rtn
diskID      EQU    *
clkID       HEX    082028005803703C
SltBit      HEX    0002040810204080

*-------------------------------------------------
* Compute autostart ROM checksum

Fndtrd      CLC
            LDY    SltBit          ;Should be zero
:loop       LDA    (look),Y        ;Point to $FB09 ("APPLE II" in ROM)
            AND    #%11011111      ;To uppercase
            ADC    SltBit
            STA    SltBit
            ROL    SltBit
            INY
            CPY    SltBit+3        ;Do for 8 bytes
            BNE    :loop

            TYA                    ;(A)=$08 now
            ASL
            ASL
            ASL
            ASL
            TAY
            EOR    SltBit          ;Turn msb on
            ADC    #$0B            ;Add a fudge factor
            BNE    :1              ;That's a clone
            LDA    apple           ;Pass the test
            RTS

:1          LDA    #$00
            RTS

*-------------------------------------------------
* Install the appropriate device-driver
* address in the system global page
* (driverAdr)= addr of driver

InstallDev  EQU    *               ;Made a sub and
            PHP                    ; how many drives (carry)
            LDA    indrcn+1        ;Get index to global device table
            AND    #$07            ; for this slot
            ASL
            TAY                    ; ... into Y-reg
            ASL
            ASL                    ;Now form device number
            ASL                    ;(A)=0SSS 0000
            JSR    staDrv
            PLP
            ROR                    ;If 2 drives, then bit7=1 (DSSS IIII)
            BPL    :1              ;Branch if a 1-drive device (i.e. profile)
            INX                    ; else presume that second drive is present
            STA    DevLst,X

:1          STX    DevCnt          ;Save updated device count
            ASL                    ;Shift # of drives back into carry
            LDA    driverAdr       ;Get low address of device driver
            STA    DevAdr01,Y
            BCC    :2              ;Branch if single drive
            STA    DevAdr02,Y
:2          LDA    driverAdr+1     ;Get high address of device driver
            STA    DevAdr01+1,Y
            BCC    :Ret
            STA    DevAdr02+1,Y
:Ret        RTS

*-------------------------------------------------
*
* This piece of code (not a subroutine) is branched to if the slot
*  search code finds a smartport device. It does a smartport status
*  call (code = 0) to determine the number of devices connected to
*  the "card". It then installs from 0..4 units in the table.
*
SmartPort   JSR    SetDevID        ;Set up the devID byte from attributes
*
* Only map more than two devices if card is in slot 5
* 
            LDA    indrcn+1        ;indrcn+1
            STA    driverAdr+1     ;Didn't set this yet

* Do the call to smartport to get the number of devices

            LDA    driverAdr
            STA    psCall+1        ;Modify operand
            CLC
            ADC    #$03
            STA    spCall+1
            LDA    driverAdr+1     ;No page cross possible
            STA    spCall+2
*********************************************
* patch 74
*********************************************
            STA    psCall+2        ;Modify operand
            ASL                    ;Convert $Cn to $n0
            ASL
            ASL
            ASL
            STA    unitNum
            STZ    dhpCmd          ;Force a ProDOS status call
            STZ    bufPtr          ;Dummy pointer
            STZ    blockNum        ;Number of bytes to transfer
            STZ    blockNum+1      ;Number of bytes to transfer
            LDA    #$10            ;Dummy pointer should be <>0
            STA    bufPtr+1        ;Dummy pointer
*********************************************
* patch 74
*********************************************
psCall      EQU    *               ;ProDOS status call
            JSR    $0000           ;Filled in by above code
            LDY    #$FB
            LDA    (indrcn),Y      ;SmartPort ID type byte
            AND    #$02            ;Is it a SCSI card?
            BEQ    :1              ;No

            STA    unitNbr         ;=2
            JSR    spCall
            DB     $00             ; Do status call on SCSI unit
            DA     spCallParms

* Determine how many devices are connected
* to the interface @ this slot
* Ref SmartPort TN #20, #21

:1          STZ    unitNbr         ;Get status of the
            JSR    spCall          ; SmartPort host
            DB     $00
            DA     spCallParms

* Don't add devices if there are none connected

            LDA    numDevices      ;Get dev cnt
            BEQ    DoneSP

* Do the first and second device if they exist

            CMP    #$02            ;C=1 if if 2,3,4
            JSR    InstallDev

* Do the third and fourth drives if they exist
*  They cannot exist for any card other than one in slot 5

            LDA    indrcn+1
            CMP    #$C5            ;If not slot 5, no mirroring
            BNE    DoneSP
********************* see note #65 *********************
*
* If this is slot 5, and if there is a disk card in slot 2,
*  only install 2 devices this slot.  Thank you.

            BIT    diskInSlot2     ;If there a disk card in slot 2?
            BPL    DoneSP          ;Yes

            LDA    numDevices
            CMP    #$03            ;More than 2 devices in slot 5?
            BCC    DoneSP          ;No (C=1 if 3,4,...)
            CMP    #$04            ;C=1 if 4,5,6,...(More than 3 devices are connected)
            LDA    #$C2            ;Make it think it's slot 2
            STA    indrcn+1
            JSR    InstallDev
            LDA    #$C5            ;Reset back to slot 5
            STA    indrcn+1
DoneSP      JMP    NxtDsk2         ;We know it's a disk device

* Ref ProDOS Tech Ref (ROM Code conventions)
*     pg 7-14 BAP

SetDevID    LDY    #$FE
SetDevIDZ   LDA    (indrcn),Y      ;Get attribute byte
            LSR
            LSR
            LSR
            LSR
            STA    devID
            RTS
**************   see note #65    ****************
*
* input:   indrcn -  point to $Cn00 of mystery card
* output:  carry    clear if disk card here, set ow
*          y        $ff
*
CmpID       LDA    CLRROM          ;Release $C800 space from previous slot
            LDY    #$05
:loop       LDA    (indrcn),Y      ;Compare ID bytes
            CMP    diskID,Y        ;$Cn07=don't care
            SEC
            BNE    :Ret            ;($Cn05)=03 
            DEY                    ;($Cn03)=00
            DEY                    ;($Cn01)=20
            BPL    :loop           ;Loop until all 4 ID bytes match
            CLC
:Ret        RTS

*-------------------------------------------------
* SmartPort parameter area

spCallParms DB     $03             ;number of parameters
unitNbr     DB     $00             ;=$00,$01-$7E
            DA     statusList
            DB     $00             ;status code = 0 (code for general status)

* Each offsets below can be considered as 000D SSS0
* Offsets for slot 0 dr1/2 & slot 3 dr 2
* are not represented here
* Slot 3 dr 2 is reserved for /RAM

mapOffset   EQU    *
            DB     $06             ;slot 3, dr 1
            DB     $1E             ;slot 7, dr 2
            DB     $0E             ;slot 7, dr 1
            DB     $1C             ;slot 6, dr 2
            DB     $0C             ;slot 6, dr 1
            DB     $1A             ;slot 5, dr 2
            DB     $0A             ;slot 5, dr 1
            DB     $14             ;slot 2, dr 2
            DB     $04             ;slot 2, dr 1
            DB     $12             ;slot 1, dr 2
            DB     $02             ;slot 1, dr 1
            DB     $18             ;slot 4, dr 2
            DB     $08             ;slot 4, dr 1

spCall      JMP    $0000

*-------------------------------------------------
* This routine will scan all slots for SmartPort
* interfaces. If more than 2 block devices are
* connected to the SmartPort Host, it will mirror
* at most 2 more block devices

ScanAll4SP  STZ    indrcn
            LDA    #$C7            ;Start w/slot 7
            STA    indrcn+1
ScanLoop    JSR    Chk4SP          ;Does slot have a SP host?
            BCS    ChkNxtSlot      ;No

            LDY    #$FF
            LDA    (indrcn),Y      ;Get LSB of block dev driver
            CLC
            ADC    #$03            ;Add 3 to get the
            STA    spCall+1        ; SmartPort entry point
            LDA    indrcn+1
            STA    spCall+2
            DEY                    ;=$FE
            JSR    SetDevIDZ       ;Get attributes
            STZ    unitNbr         ;Get status of SmartPort Host
            JSR    spCall
            DB     $00
            DA     spCallParms

            LDA    numDevices
            CMP    #$03            ;More than 2 devices?
            BCC    ChkNxtSlot      ;No
            INC                    ;1 more for easier comparision
            STA    maxUnitP1       ;=4,5,6,...
            LDA    #$03
            LDX    spCall+2
            CPX    #$C5            ;Slot 5?
            BNE    ChkDevLoop      ;No
            BIT    diskInSlot2     ;If there a disk card in slot 2?
            BPL    ChkDevLoop      ;Yes

* Slot 5 and no disk card in slot 2.
* 4 of the devices connected to this
* slot had already been dealt with.

            LDA    #$05
ChkDevLoop  CMP    maxUnitP1
            BCS    ChkNxtSlot

            STA    unitNbr         ;Get device status of this unit 
            JSR    spCall          ;Ref pg 122 IIGS Firmware
            DB     $00             
            DA     spCallParms
            LDA    spDevStatus     ;Is it block dev?
            BMI    MirrorDev       ;Yes

* No, it's a char dev

CkNxtChnDev LDA    unitNbr
            INC
            BRA    ChkDevLoop      ;Loop to check next dev in chain

ChkNxtSlot  DEC    indrcn+1        ;Set up for next lower slot
            LDA    indrcn+1
            CMP    #$C0            ;Have all slots been checked?
            BNE    ScanLoop        ;No
            RTS

*-------------------------------------------------
* We have more than 2 devices connected to
*  the SmartPort Host in this slot

MirrorDev   LDX    #12             ;Search thru 13 entries
MirrorLoop  LDY    mapOffset,X     ;Get offset
            LDA    DevAdr01,Y      ;Check if there is an 
            CMP    #<gNoDev        ; unassigned entry in table
            BNE    NoMapping       ;No, already filled
            LDA    DevAdr01+1,Y
            CMP    #>gNoDev
            BEQ    MapDevice       ;Got an available entry
NoMapping   DEX
            BPL    MirrorLoop
            RTS

*-------------------------------------------------
* Install SmartPort driver for additional
* block devices connected to slot

MapDevice   LDA    indrcn+1        ;Save slot #
            PHA
            PHX
            PHY
            TYA
            LSR                    ;0000 DSSS
            AND    #$07            ;0000 0SSS
            ORA    #$C0
            STA    indrcn+1        ;Chk if there is a SmartPort
            JSR    Chk4SP          ; Host in this slot
            PLY
            PLX
            PLA
            STA    indrcn+1
            BCC    NoMapping       ;Yes, don't mirror the dev

            JSR    LC1In           ;Switch in LC bank 1
            TYA                    ;000D SSS0
            LSR
            TAX                    ;0000 DSSS ($01-$0F; $00,$08,$0B-invalid)
            LDA    unitNbr
            STA    spUnits-1,X
            LDA    spCall+1        ;Save actual SmartPort driver
            STA    spDrvAdrL-1,X
            LDA    spCall+2
            STA    spDrvAdrH-1,X
            LDA    RDROM2
            INC    DevCnt
            LDX    DevCnt
            TYA
            LSR                    ;0000 DSSS
            CMP    #$08
            BCC    :1              ;Drive 1
            SBC    #$08
            ORA    #$08            ;Add back drive 2 bit
:1          ASL
            ASL
            ASL
            ASL
            ORA    devID           ;DSSS IIII
            STA    DevLst,X
            LDA    #<MirrorDevEntry;Install driver that
            STA    DevAdr01,Y      ; handles the mirrored devices
            LDA    #>MirrorDevEntry
            STA    DevAdr01+1,Y
            BRA    CkNxtChnDev

*-------------------------------------------------
* Exit
*  C=0 if there is a SmartPort card/interface
*      in the slot

Chk4SP      JSR    CmpID
            BCS    :Rtn            ;No disk card in this slot
            SEC
            LDY    #$07            ;Is this the SmartPort
            LDA    (indrcn),Y      ; signature byte?
            BNE    :Rtn            ;No
            CLC
:Rtn        RTS