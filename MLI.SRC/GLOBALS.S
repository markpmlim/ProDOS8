            TTL    'Global pages - 64K'

            ORG    Globals
**************************************************

GoPro       JMP    mliEnt1         ;MLI call entry point

************ see rev note #36 ********************
* Jump vector to cold start/selector program, etc. Will
* be changed to point to dispatcher caller by the loader

jSpare      JMP    jSpare
*-------------------------------------------------
DateTime    DB     $60             ;Changed to $4C (JMP) if clock present
            DA     ClockBegin      ;Clock routine entry address
SysErr      JMP    SysErr1         ;Error reporting hook
SysDeath    JMP    SysDeath1       ;System failure hook
SErr        DB     $00             ;Error code, 0=no error

*-------------------------------------------------
DevAdr01    EQU    *
            DA     gNoDev          ;slot zero reserved
            DA     gNoDev          ;slot 1, drive 1
            DA     gNoDev          ;slot 2, drive 1
            DA     gNoDev          ;slot 3, drive 1
            DA     gNoDev          ;slot 4, drive 1
            DA     gNoDev          ;slot 5, drive 1
            DA     gNoDev          ;slot 6, drive 1
            DA     gNoDev          ;slot 7, drive 1
DevAdr02    DA     gNoDev          ;slot zero reserved
            DA     gNoDev          ;slot 1, drive 2
            DA     gNoDev          ;slot 2, drive 2
DevAdr32    DA     gNoDev          ;slot 3, drive 2
            DA     gNoDev          ;slot 4, drive 2
            DA     gNoDev          ;slot 5, drive 2
            DA     gNoDev          ;slot 6, drive 2
            DA     gNoDev          ;slot 7, drive 2

*-------------------------------------------------
* Configured device list by device number
* Access order is last in list first.

DevNum      DB     $00             ;Most recently accessed device
DevCnt      DB     $FF             ;Number of on-line devices (minus 1)
DevLst      HEX    0000000000      ;Up to 14 units may be active
            HEX    0000000000
            HEX    00000000
            DB     0               ;Unused?
            ASC    '(C)APPLE        ' ; AppleTALK writes over this area! DO NOT MOVE!

*-------------------------------------------------
mliEnt1     PHP
            SEI                    ;Disable interrupts
            JMP    mliCont
aftIrq      STA    LCBANK1
            JMP    fix45           ;Restore $45 after interrupt in lang card*

old45       DB     $00
afBank      DB     $00

*-------------------------------------------------
* Memory map of the lower 48K. Each bit represents one page
* (256 bytes) of memory. Protected areas are marked with a
* 1, unprotected with a 0. ProDOS dis-allows reading or
* buffer allocation in protected areas.

memTabl     HEX    C000000000000000
            HEX    0000000000000000
            HEX    0000000000000001

* The addresses contained in this table are buffer addresses
* for currently open files. These are informational only,
* and should not be changed by the user except through the 
* MLI call setbuf.

GblBuf      DA     $0000           ;file number 1
            DA     $0000           ;file number 2
            DA     $0000           ;file number 3
            DA     $0000           ;file number 4
            DA     $0000           ;file number 5
            DA     $0000           ;file number 6
            DA     $0000           ;file number 7
            DA     $0000           ;file number 8

*-------------------------------------------------
* Interrupt vectors are stored here. Again, this area is
* informational only, and should be changed only by calls
* to the MLI to allocate_interrupt. Values of the A, X, Y,
* stack, and status registers at the time of the most recent
* interrupt are also stored here. In addition, the address
* interrupted is also preserved. These may be used for
* performance studies and debugging, but should not be changed
* by the user.

Intrup1     DA     $0000           ;interupt routine 1
Intrup2     DA     $0000           ;interupt routine 2
Intrup3     DA     $0000           ;interupt routine 3
Intrup4     DA     $0000           ;interupt routine 4
IntAReg     DB     $00             ;A-register
IntXReg     DB     $00             ;X-register
IntYReg     DB     $00             ;Y-register
IntSReg     DB     $00             ;Stack register
IntPReg     DB     $00             ;Status register
IntBankID   DB     $01             ;ROM, RAM1, or RAM2 ($D000 in LC)
IntAddr     DA     $0000           ;program counter return addr

*-------------------------------------------------
* The user may change the following options
* prior to calls to the MLI.

DateLo      DW     $0000           ;bits 15-9=yr, 8-5=mo, 4-0=day 
TimeLo      DW     $0000           ;bits 12-8=hr, 5-0=min; low-hi format
Level       DB     $00             ;File level: used in open, flush, close
BUBit       DB     $00             ;Backup bit disable, setfileinfo only
Spare1      DB     $00             ; Used to save A reg
NewPfxPtr   DB     $00             ;Used as AppleTalk alternate prefix ptr

* The following are informational only.  MachID identifies
* the system attributes:
* (bit 3 off) bits 7,6-  00=ii  01=ii+   10=iie   11=/// emulation
* (bit 3 on)  bits 7,6-  00=na  01=na    10=//c   11=na
*             bits 5,4-  00=na  01=48k   10=64k   11=128k
*             bit  3    modifier for machid bits 7,6. 
*             bit  2    reserved for future definition. 
*             bit  1=1-  80 column card
*             bit  0=1-  recognizable clock card
*
* SltByt indicates which slots are determined to have ROMs.
* PfixPtr indicates an active prefix if it is non-zero.
* mliActv indicates an mli call in progress if it is non-zero.
* CmdAdr is the address of the last mli call's parameter list.
* SaveX and SaveY are the values of x and y when the MLI 
*  was last called.

MachID      DB     $00             ;Machine identification
SltByt      DB     $00             ;'1' bits indicate rom in slot(bit#)
PfixPtr     DB     $00             ;If = 0, no prefix active...
mliActv     DB     $00             ;If <> 0, MLI call in progress
CmdAdr      DA     $0000           ;Return address of last call to MLI
SaveX       DB     $00             ;X-reg on entry to MLI
SaveY       DB     $00             ;Y-reg on entry to MLI

*-------------------------------------------------
* The following space is reserved for language card bank
* switching routines. All routines and addresses are
* subject to change at any time without notice and will, 
* in fact, vary with system configuration.
* The routines presented here are for 64K systems only. 

Exit        EOR    $E000           ;Test for ROM enable
            BEQ    Exit1           ;Branch if RAM enabled
            STA    RDROM2          ;else enable ROM and return
            BNE    Exit2           ;Branch always

Exit1       LDA    BnkByt2         ;For alternate RAM enable
            EOR    $D000           ; (mod by mliEnt1)
            BEQ    Exit2           ;Branch if not alternate RAM
            LDA    LCBANK2         ;else enable alt $D000

Exit2       PLA                    ;Restore return code
            RTI                    ;Re-enable interrupts and return

mliCont     SEC
            ROR    mliActv         ;Indicate to interrupt routines MLI active
rpmCont     LDA    $E000           ;Preserve language card / ROM
            STA    BnkByt1         ; orientation for proper
            LDA    $D000           ; restoration when MLI exits...
            STA    BnkByt2
            LDA    LCBANK1         ;Now force ram card on
            LDA    LCBANK1         ; with RAM write allowed
            JMP    EntryMLI

irqXit      LDA    IntBankID       ;Determine state of RAM card
IrqXit0     BEQ    IrqXit2         ; if any. Branch if enabled
            BMI    IrqXit1         ;Branch if alternate $D000 enabled
            LSR                    ;Determine if no RAM card present
            BCC    ROMXit          ;Branch if ROM only system
            LDA    ROMIN2          ;else enable ROM first
            BCS    ROMXit          ;Branch always taken...
IrqXit1     LDA    LCBANK2         ;Enable alternate $D000
IrqXit2     LDA    #$01            ;Preset bankid for ROM
            STA    IntBankID       ;(reset if RAM card interupt)
ROMXit      LDA    IntAReg         ;Restore accumulator...
            RTI                    ; and exit!

IrqEnt      BIT    LCBANK1         ;This entry only used when ROM
            BIT    LCBANK1         ; was enabled at time of interupt
            JMP    IrqRecev        ; A-reg is stored at $45 in zpage

*-------------------------------------------------
BnkByt1     DB     $00
BnkByt2     DB     $00
            DS     $BFFA-*,0       ; pad
            DB     $04             ;Referenced by GS/OS
            DB     $00

iBakVer     DB     $00             ;Reserved
iVersion    DB     $00             ;Version # of currently running interpreter
kBakVer     DB     $00             ;Undefined: reserved for future use
kVersion    DB     $23             ;Represents release 2.03
