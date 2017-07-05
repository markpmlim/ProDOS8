* * * * * * * * * * * * * * * * *
*    The xdos machine language  *
*         interface (MLI)       *
*      system call processor    *
* * * * * * * * * * * * * * * * *

            ORG    orig1
            MX     %11
EntryMLI    CLD                    ;Cannot deal with decimal mode!!!
            PLA                    ;Get processor status
            STA    Spare1          ;Save it on the global page temporarily
            STY    SaveY           ;Preserve the y and x registers
            STX    SaveX
            PLA                    ;Find out the address of the caller
            STA    parm
            CLC                    ; & preserve the address of the call spec
            ADC    #$04
            STA    CmdAdr
            PLA
            STA    parm+1
            ADC    #$00
            STA    CmdAdr+1        ;CmdAdr is in the globals

*  Check cmd code

            LDA    Spare1
            PHA
            PLP                    ;Pull processor to re-enable interrupts
            CLD                    ;No decimal! (** #46 **)
            LDY    #$00
            STY    SErr            ;Clear any previous errors...

* Hashing algorithm used here adds high nibble
* (div by 16 first) to the whole cmd code
* and then masks it to 5 lower bits
* This compresses range of codes without any overlapping

            INY                    ;Find out if we've got a valid command
            LDA    (parm),Y        ;Get command #
            LSR                    ;Hash it to a range of $00-$1F
            LSR
            LSR
            LSR
            CLC
            ADC    (parm),Y
            AND    #$1F
            TAX
            LDA    (parm),Y        ;Now see if result is a valid command number
            CMP    scNums,X        ;Should match if it is
            BNE    scnErr          ;Branch if not

*  Get IOB address

            INY                    ;Index to call spec parm list addr
            LDA    (parm),Y        ;Make parm point to parameter count byte
            PHA                    ; in parameter block
            INY
            LDA    (parm),Y
            STA    parm+1
            PLA
            STA    parm

*  Check parm count

            LDY    #c_pCnt         ;Now make sure parameter list has the
            LDA    pCntTbl,X       ;  proper number of parameters
            BEQ    GoClock         ;Clock has 0 parameters
            CMP    (parm),Y
            BNE    scpErr          ;Report error if wrong count

* Check class of function

            LDA    scNums,X        ;Get call number again
            CMP    #$65
            BEQ    Special
            ASL                    ;Carry set if bfm or dev mgr
            BPL    GoDevMgr
            BCS    GoBFMgr
            LSR                    ;Shift back down for interupt mgr

* Isolate type
* 0-alloc, 1-dealloc, 2-special

            AND    #$03            ;Valid calls are 0 & 1
            JSR    IntMgr
            BRA    ExitMLI         ;Command processed, all done
Special     JMP    jSpare          ;QUIT

**************************************************
* Command $82 - Get the date and time

GoClock     JSR    DateTime        ;go read clock
            BRA    ExitMLI         ;No errors posible!

**************************************************
* READBLOCK and WRITEBLOCK commands ($80 and $81)

GoDevMgr    LSR                    ;Save command #
            ADC    #$01            ;Valid commands are 1 & 2
            STA    dhpCmd          ;(READ & WRITE)
            JSR    DevMgr          ;Execute read or write request
            BRA    ExitMLI

*-------------------------------------------------
* Commands $C0 thru $D3

GoBFMgr     LSR
            AND    #$1F            ;Valid commands in range of $00-$13
            TAX
            JSR    BFMgr           ;Go do it...

ExitMLI     STZ    BUBit           ;First clear bubit
            LDY    SErr            ;Y holds error code thru most of exit
            CPY    #$01            ;If >0 then set carry
            TYA                    ; & set z flag
            PHP                    ;Disable interupts
            SEI                    ; until exit complete
            LSR    mliActv         ;Indicate MLI done.(** #46 **) (** #85 **)
            PLX                    ;Save status register in X
            LDA    CmdAdr+1        ; until return address is placed
            PHA                    ; on the stack returning is done via 'RTI'
            LDA    CmdAdr          ; so that the status register is
            PHA                    ; restored at the same time
            PHX                    ;Place status back on the stack
            TYA                    ;Return error, if any
            LDX    SaveX           ;Restore x & y registers
            LDY    SaveY
ExitRPM     PHA                    ; (exit point for rpm **en3**)
            LDA    BnkByt1         ;Restore language card status & return
            JMP    Exit

*-------------------------------------------------

gNoDev      LDA    #drvrNoDevice   ;Report no device connected
            JSR    SysErr
scnErr      LDA    #badSystemCall  ;Report no such command
            BNE    scErr1          ;Branch always
scpErr      LDA    #invalidPcount  ;report parameter count is invalid
scErr1      JSR    GoSysErr
            BCS    ExitMLI         ;Branch always taken

            TTL    'ProDOS Device Manager'

*-------------------------------------------------
* ProDOS device manager
* Block I/O setup

DevMgr      LDY    #$05            ;The call spec for devices must
            PHP                    ;(do not allow interupts)
            SEI
:loop       LDA    (parm),Y        ; be passed to drivers in zero page
            STA    |dhpCmd,Y       ;dhpCmd,unitNum,bufPtr,blockNum
            DEY
            BNE    :loop
            LDX    bufPtr+1
            STX    userBuf+1
            INX
            INX                    ;Add 2 for 512 byte range
            LDA    bufPtr          ;Is buffer page alligned?
            BEQ    :1              ;Branch if it is
            INX                    ;Else account for 3-page straddle...
:1          JSR    ValDBufZ        ;Make sure user is not conflicting
            BCS    DevMgrErr       ; with protected RAM
            JSR    DMgr            ;Call internal entry for device dispatch
            BCS    DevMgrErr       ;Branch if error occured
            PLP
            CLC                    ;Make sure carry is clear (no error)
            RTS

DevMgrErr   PLP
GoSysErr    JSR    SysErr

*-------------------------------------------------
* NOTE: interrupts must always be off when entering here
* Do block I/O rtn

DMgr        LDA    unitNum         ;Get device number
            AND    #$F0            ;Strip misc lower nibble
            STA    unitNum         ;  & save it back
            LSR                    ;Use as index to device table
            LSR
            LSR
            TAX
            LDA    DevAdr01,X      ;Fetch driver address
            STA    goAdr
            LDA    DevAdr01+1,X
            STA    goAdr+1
GoCmd       JMP    (goAdr)         ;Goto driver (or error if no driver)

            TTL    'ProDOS Interrupt Manager'
*-------------------------------------------------
* ProDOS interrupt manager
* Handle ALLOC_INTERRUPTS ($40) and
* DEALLOC_INTERRUPTS ($41) Calls

IntMgr      STA    intCmd          ;Allocate intrupt or deallocate?
            LSR                    ;(A=0, carry set=dealloc)
            BCS    DeAlocInt       ;Branch if deallocation
            LDX    #$03            ;Test for a free interupt space in table
AlocInt     LDA    Intrup1-2,X     ;Test high addr for zero
            BNE    :1              ;Branch if spot occupied
            LDY    #c_intAdr+1     ;Fetch addr of routine
            LDA    (parm),Y        ;Must not be in zero page!!!!
            BEQ    BadInt          ;Branch if the fool tried it
            STA    Intrup1-2,X     ;Save high address
            DEY
            LDA    (parm),Y
            STA    Intrup1-3,X     ; & low address
            TXA                    ;Now return interupt # in range of 1 to 4
            LSR
            DEY
            STA    (parm),Y        ;Pass back to user
            CLC                    ;Indicate success!
            RTS

:1          INX
            INX                    ;Bump to next lower priority spot
            CPX    #$0B            ;Are all four allocated already?
            BNE    AlocInt         ;Branch if not

            LDA    #irqTableFull   ;Return news that four devices are active
            BNE    IntErr1

BadInt      LDA    #paramRangeErr  ;Report invalid parameter
IntErr1     JSR    SysErr

DeAlocInt   LDY    #c_intNum       ;Zero out interupt vector
            LDA    (parm),Y        ; but make sure it is valid #
            BEQ    BadInt          ;Branch if it's <1
            CMP    #$05            ; or >4
            BCS    BadInt
            ASL
            TAX
            LDA    #$00            ;Now zip it
            STA    Intrup1-2,X
            STA    Intrup1-1,X
            CLC
            RTS

*-------------------------------------------------
* IRQ Handler - If an IRQ occurs, we eventually get HERE

IrqRecev    LDA    Acc             ;Get Acc from 0-page where old ROM put it
            STA    IntAReg
            STX    IntXReg         ;Entry point on RAM card interupt
            STY    IntYReg
            TSX
            STX    IntSReg
            LDA    IrqFlag         ;Irq flag byte = 0 if old ROMs
            BNE    :1              ;  and 1 if new ROMs
            PLA
            STA    IntPReg
            PLA
            STA    IntAddr
            PLA
            STA    IntAddr+1
:1          TXS                    ;Restore return addr & p-reg to stack
            LDA    MSLOT           ;Set up to re-enable $cn00 rom
            STA    IrqDev+2
            TSX                    ;Make sure stack has room for 16 bytes
            BMI    NoStkSave       ;Branch if stack safe
            LDY    #16-1
StkSave     PLA
            STA    SvStack,Y
            DEY
            BPL    StkSave

NoStkSave   LDX    #$FA            ;Save 6 bytes of zero page
ZPgSave     LDA    $00,X
            STA    SvZeroPg-$FA,X
            INX
            BNE    ZPgSave

* Poll interupt routines for a claimer

            LDA    Intrup1+1       ;Test for valid routine
            BEQ    :1              ;Branch if no routine
            JSR    goInt1
            BCC    IrqDone
:1          LDA    Intrup2+1       ;Test for valid routine
            BEQ    :2              ;Branch if no routine
            JSR    goInt2          ;Execute routine
            BCC    IrqDone
:2          LDA    Intrup3+1       ;Test for valid routine
            BEQ    :3              ;Branch if no routine
            JSR    goInt3
            BCC    IrqDone
:3          LDA    Intrup4+1       ;Test for valid routine
            BEQ    IrqDeath        ;Branch if no routine
            JSR    goInt4          ;Execute routine
            BCC    IrqDone

*************** see rev note #35 *************************

IrqDeath    INC    IrqCount        ;Allow 255 unclaimed interrupts
            BNE    IrqDone         ; before going to system death...
            LDA    #unclaimedIntErr
            JSR    SysDeath

* IRQ processing complete

IrqDone     LDX    #$FA
:loop       LDA    SvZeroPg-$FA,X
            STA    $00,X
            INX
            BNE    :loop
            LDX    IntSReg         ;Test for necessity of restoring stack elements
            BMI    :1
            LDY    #$00
:loop2      LDA    SvStack,Y
            PHA
            INY
            CPY    #16
            BNE    :loop2

:1          LDA    IrqFlag         ;Check for old ROMs
            BNE    IrqDoneX        ;Branch if new ROMs

* Apple II or II+ monitor

            LDY    IntYReg         ;Restore registers
            LDX    IntXReg
            LDA    CLRROM          ;Re-enable I/O card
IrqDev      LDA    $C100           ;Warning, self modified
            LDA    IrqDev+2        ;Restore device ID
            STA    MSLOT
IrqDoneX    JMP    irqXit

IrqFlag     DB     $00             ;irq flag byte. 0=old ROMs; 1=new ROMs
IrqCount    DB     $00             ;Unclaimed interrupt counter.(note #35)
SvStack     DS     16,0
SvZeroPg    DS     6,0

goInt1      JMP    (Intrup1)
goInt2      JMP    (Intrup2)
goInt3      JMP    (Intrup3)
goInt4      JMP    (Intrup4)

*-------------------------------------------------
* System error handler

SysErr1     STA    SErr
            PLX
            PLX                    ;Pop 1 level of return
            SEC
            RTS

*-------------------------------------------------
* System death handler

SysDeath1   TAX                    ;System death!!!
            STA    CLR80VID        ;Force 40 columns on rev-e
            LDA    TXTSET          ;Text mode on
            LDA    cortFlag        ;Check if we're on a cortland
            BEQ    NoSupHires
            STZ    NEWVIDEO        ;Force off SuperHires
NoSupHires  LDA    TXTPAGE1        ;Display page 1 on
            LDY    #$13
DspDeath    LDA    #'              '
            STA    SLIN10+10,Y
            STA    SLIN12+10,Y
            LDA    Death,Y
            STA    SLIN11+10,Y
            DEY
            BPL    DspDeath
            TXA
            AND    #$0F
            ORA    #"0"
            CMP    #"9"+1
            BCC    :1              ;Branch if not >9
            ADC    #$06            ;Bump to alpha A-F
:1          STA    SLIN11+28
Halt        BRA    Halt            ;Hold forever
