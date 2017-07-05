**************************************************
* New GS/OS Dispatcher for P8

GQuit8      EQU    $E0D000

            ORG    DispAdr
            XC
            XC
GS_Disp     LDA    LCBANK1         ;Enable read
            CLC
            XCE
            JMPL   GQuit8

            DS     5,0             ;Pad with spaces

gqSign      ASC    'GQ'            ;Signature word

*-------------------------------------------------
* Control is passed back here by GQuit8
* after it has setup the required parameters

            MX     %10
GS_DispZ    SEP    #$20            ;8-bit A, 16-bit index regs
            PHA
            LDX    #inBuf          ;Boot Volname
            JSR    GetVolName
            PLA
            SEC                    ;Emulation mode
            XCE
            ORA    #$00            ;Nil prefix?
            BEQ    :1

            MX     %11
:loop       JSR    GoPro
            DB     $C6
            DA     SPfxParm
            BCC    :1

            JSR    ShowAlrt
            BRA    :loop

:1          XCE
            MX     %10
            REP    #$10            ;16-bit index regs
            LDA    pnBuf+1         ;Application's name is passed here
            CMP    #'/'            ;Does it begin with a slash?
            BNE    :2              ;No, so a partial PN is passed
            LDX    #pnBuf          ;Full PN is passed
            JSR    GetVolName      ;Application's vol name

:2          SEC                    ;Full emulation mode
            XCE

Try2Open    JSR    GoPro
            DB     $C8
            DA     OpenParm
            BCC    Opened
            JSR    ShowAlrt
            BRA    Try2Open

Opened      LDA    OpenRefNbr
            STA    eofRefNbr
            STA    ReadRefNbr
            STA    ClsRefNbr

GetFileLen  JSR    GoPro
            DB     $D1
            DA     eofParm
            BCC    GotFileLen
            JSR    ShowAlrt
            BRA    GetFileLen

GotFileLen  LDA    theEOF
            STA    ReadLen
            LDA    theEOF+1
            STA    ReadLen+1

Try2Read    JSR    GoPro
            DB     $CA
            DA     ReadParm
            BCC    Try2Cls
            JSR    ShowAlrt
            BRA    Try2Read

Try2Cls     JSR    GoPro
            DB     $CC
            DA     ClsParm
            BCC    ClsOK
            JSR    ShowAlrt
            BRA    Try2Cls

ClsOK       JSR    Chk4Intrp
            BNE    RunApp          ;It's not an Interpreter eg BI
            JSR    GetStartup      ;Get the startup pgm
            BCC    RunApp          ;Transfer control to Interpreter
            LDA    #volNotFound
            BRA    ShwErrAlrt

RunApp      LDA    RDROM2          ;Enable motherboard ROM
            JMP    $2000           ;Pass control to SYS application

*-------------------------------------------------
* (A)=Error Code
* Report Err & Quit

ShowAlrt    CLC
            XCE
            REP    #$30            ;Full 16-bit native mode
            JSR    Ask4Disk
            BCS    ShwErrAlrt
            SEC                    ;Back to emulation mode
            XCE
            RTS

*-------------------------------------------------
* Put up a text box showing an error code
* (A)=err code. It calls P8's quit code

ShwErrAlrt  CLC
            XCE
            REP    #$30            ;Full 16-bit native mode
            AND    #$00FF
            PHA                    ;Convert err code
            PushLong               #ErrNumStr
            PushWord               #4 ; into 4-byte ASCIIs char
            _Int2Hex

            PHA
            PushLong               #CantRunStr ;line1Ptr
            PushLong               #P8ErrStr ;line2Ptr
            PushLong               #acceptStr ;button1Ptr
            PushLong               #nullStr ;button2Ptr
            _TLTextMountVol
            PLA                    ;Not used
            SEC                    ;Emulate 65C02
            XCE

            JSR    GoPro
            DB     $65
            DA     QuitParms

*-------------------------------------------------
* On entry
*  (A)=Error Code

            MX     %00
Ask4Disk    LDY    #$0000          ;ptr to volname
            LDX    #VolNameStr
            AND    #$00FF          ;Err #
            CMP    #volNotFound
            BEQ    :1
            CMP    #drvrOffLine
            BEQ    :1
            SEC
            RTS

* Prompt for correct vol

:1          PHA                    ;Err code
            PHY
            PHX
            TSC
            PHD
            TCD
            LDA    [$01]           ;Get len byte
            DEC
            XBA
            STA    [$01]
            PHA                    ;word result
            PushLong               #insDskStr ;line1Ptr
            PHY
            INX
            PHX                    ;(Y,X) line2Ptr
            PushLong               #acceptStr ;button1Ptr
            PushLong               #cancelStr ;button2Ptr
            _TLTextMountVol
            LDA    [$01]
            XBA
            INC
            STA    [$01]
            PLA                    ;button # chosen
            PLD
            PLX
            PLX
            CMP    #$0001          ;Return?
            BNE    NotRet          ;No, Esc
            CLC
            PLA                    ;err #
            RTS

NotRet      SEC
            PLA                    ;err #
            RTS

*-------------------------------------------------
* Called with 8-bit Acc but 16-bit index regs
* (X)=16-bit mem location to PN
* Copies just the volname to our buf
* On return, (A)=len of volname
* This rtn will hang if there is no
* trailing slash

            MX     %10
GetVolName  LDA    |$0001,X        ;Get prefix char (if any)
            STA    VolNameStr+1
            LDY    #$0002
:loop       LDA    |$0002,X        ;Get char
            CMP    #'/'            ;Is it a trailing slash?
            BEQ    :Done           ;Yes
            STA    VolNameStr,Y
            INX
            INY
            BRA    :loop

:Done       DEY                    ;backup 1
            TYA
            STA    VolNameStr      ;Set len byte
            RTS

*-------------------------------------------------
* Application File was already loaded in mem @ $2000
* If it is an interpreter, the Tool Locator is check
* for the name of the program which will be launched
* by the interpreter. For example, click on a file
* with type BAS with cause the BI to be loaded &
* executed. BI will launch the BASIC program which
* is passed via MessageCenter call of Tool Locator
*
* Z=0 Application is not an interpreter
* Z=1 Success
* Ref: pg 88 ProDOS 8 Technical Reference Manual

Chk4Intrp   LDA    $2000           ;Check if it's an interpreter
            CMP    #$4C            ;JMP inst
            BNE    :Rtn
            LDA    #$EE            ;INC inst
            CMP    $2003
            BNE    :Rtn
            CMP    $2003+1
            BEQ    :1
:Rtn        RTS

:1          LDA    #$FF            ;Init ErrFlag & push
            PHA                    ; onto stack for later
            CLC
            XCE
            REP    #$30            ;Full native mode
            PHA
            _MMStartUp
            PLA                    ;user ID

* Ref IIGS Toolbox Vol 2 pg 24-14
*     IIGS Toolbox Vol 3 pg 52-4
* Any size for the message handle will do
* since MessageCenter will resize it

            PHA                    ;Push back for later
            PHA                    ;long result
            PHA
            PushLong               #10 ;# of bytes to allocate
            PHA                    ;userID
            PushWord               #$0000 ;attr
            PHA
            PHA
            _NewHandle
            PLA                    ;msg hndl
            PLX
            BCS    ShutDnMM

            PHX
            PHA
            PushWord               #2 ;action=Get
            PushWord               #1 ;msgID=file
            PHX                    ;msg Hndl
            PHA
            _MessageCenter
            BCS    DumpMsgHndl

            PHA                    ;work space
            PHA                    ; for ptr
            TSC
            PHD
            INC
            TCD
*
* DP Space:
* |--------------|
* |   ErrFlag    | B
* |--------------|
* |    userID    | 9-A
* |--------------|
* |   msgHndl    | 4-7
* |--------------|
* |    2 PHA's   | 0-3
* |--------------|
*

            LDA    [$04]           ;Deref the mem handle
            STA    $00
            LDY    #$0002
            LDA    [$04],Y
            STA    $00+2

                                   ; Ref Vol 2 pg 24-15

            LDY    #$0006
            LDA    [$00],Y         ;Get printFlag
            BNE    DelMsg
            LDA    $00             ;Open
            CLC
            ADC    #$0008
            STA    $00             ;Point @ name (pString)
            BCC    :2
            INC    $00+2

:2          LDA    [$00]
            AND    #$00FF          ;Isolate len byte
            SEP    #$20            ;NB. 8-bit Acc
            CMP    $2003+2         ;Are the lens same?
            BEQ    :3              ;Yes
            BCS    DelMsg          ;No

:3          TAY
:CpyLoop    LDA    [$00],Y         ;Copy PN of
            STA    $2000+6,Y       ; pgm for Interpreter
            STA    inBuf,Y         ; to run
            DEY
            BPL    :CpyLoop

*
*  Stack contents:
* |              |
* |--------------|
* |   ErrFlag    | D
* |--------------|
* |    userID    | B-C
* |--------------|
* |   msgHndl    | 7-A
* |--------------|
* |   2 PHA's    | 3-6
* |--------------|
* |   DP reg     | 1-2
* |--------------|
* |              |<- SP
*
            LDA    #$00            ;Overwrite ErrFlag
            STA    $0D,S           ; which was $FF

DelMsg      REP    #$20            ;16-bit Acc
            PLD
            PLA
            PLA
            PushWord               #3 ;action=delete
            PushWord               #1 ;type=file
            PHA
            PHA
            _MessageCenter

DumpMsgHndl _DisposeHandle         ;msgHndl
ShutDnMM    _MMShutDown            ;userID still on stack

            MX     %11
            SEC                    ;Full emulation mode
            XCE
            PLA                    ;Get ErrFlag
            BNE    :Ret

            LDX    inBuf           ;Get len byte
            LDA    #'/'
:CpyLoop    CMP    inBuf,X         ;Look for a trailing slash
            BEQ    :1              ;Got one
            DEX
            BNE    :CpyLoop
            BRA    :Ret

:1          DEX                    ;Backup 1
            STX    inBuf           ;len byte of vol name
            JSR    GoPro
            DB     $C6
            DA     SPfxParm
            LDA    #$00            ;Flag no errs
:Ret        RTS

*-------------------------------------------------
* Get the name of startup program that will be
* launched by an interpreter. Verify it's there.
* BI will look for a BASIC program called STARTUP
* C=0 - Success

GetStartup  CLC                    ;Native mode
            XCE
            REP    #$10
            LDX    #$2000+6        ;Get full/partial PN
            JSR    GetVolName      ; of startup program

:loop       SEC                    ;Full emulation mode
            XCE
            JSR    GoPro
            DB     $C4
            DA     GFIParm
            BCC    :Rtn

            CLC
            XCE
            REP    #$30            ;Full 16-bit native mode
            JSR    Ask4Disk        ;Ask for disk w/startup pgm
            BCC    :loop

            SEC                    ;Back to emulation mode
            XCE
            SEC                    ;Flag failure
:Rtn        RTS

*-------------------------------------------------
* ProDOS8 Parm tables

SPfxParm    DB     $01
            DA     inBuf

OpenParm    DB     $03
            DA     pnBuf           ;Application's PN
            DA     IOBuf           ;1024-byte I/O buf
OpenRefNbr  DB     $00

eofParm     DB     $02
eofRefNbr   DB     $00
theEOF      DB     0,0,0

ReadParm    DB     $04
ReadRefNbr  DB     $00
            DA     $2000           ;Read into this location
ReadLen     DW     $0000
            DW     $0000

ClsParm     DB     $01
ClsRefNbr   DB     $00

QuitParms   DB     $04
            DB     $00             ;=$EE for enhanced Quit
            DA     $0000           ;Addr of pathname
            DB     $00
            DW     $0000

GFIParm     DB     $0A
            DA     VolNameStr
            DB     $00
            DB     $00
            DW     $0000
            DB     $00
            DW     $0000
            DW     $0000
            DW     $0000
            DW     $0000
            DW     $0000

* Messages/Button strings

CantRunStr  STR    'Can'27't       run next application.'
P8ErrStr    DB     20              ;len byte
            ASC    'ProDOS         Error = $'
ErrNumStr   ASC    '                  '
nullStr     DB     $00
insDskStr   STR    'Please         insert the disk:'
acceptStr   DB     13
            ASC    'Accept:        '
            HEX    1B              ;Enable mousetext chars
            HEX    0F              ;Inverse
            ASC    'M'             ;Return Icon
            HEX    0E              ;Normal
            HEX    18              ; ;Disable mousetext chars
cancelStr   STR    'Cancel:        Esc'