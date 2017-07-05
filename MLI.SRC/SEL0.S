***********************************************************
*                                                         *
*          PRODOS 8 LOBOTOMIZED DISPATCHER ROUTINE        *
*                                                         *
*           COPYRIGHT APPLE COMPUTER, INC., 1983-86       *
*                                                         *
*                    ALL RIGHTS RESERVED                  *
*                                                         *
***********************************************************

            TTL    "DISPATCHER I"
***********************************************************
*
*  DISPATCHER 1 - This code ORGs and operates at $1000 but
*    is resident in memory at $D100 in the Alt 4K bank of the
*    Language Card.  The QUIT call vectors to a routine high
*    in the MLI that moves DISPATCHER 1 down and jumps to it.
*    The move routine MUST remain somewhere between $E000-$F7FF.
*
*  NOTE: This entire routine MUST remain no larger than 3 pages.
*
***********************************************************

            ORG    $1000
            MX     %11
HereIn      LDA    RDROM2
            STA    CLR80VID        ;Disable 80 column hardware
            STA    CLRALTCHAR      ;Switch in primary char set
            STA    CLR80COL        ;Disable 80 column store
            JSR    SetNorm         ;Normal white chars on black background
            JSR    Init            ;Text pg1; text mode; set 40 col window
            JSR    SetVid          ;Does a PR#0 (puts COUT1 in CSW)
            JSR    SetKBD          ;Does an IN#0 to set Basic input to kbd
****************************************************
*
*  Clear the memory Bit Map

ClrMap      LDX    #$17            ;Do all the bytes
            LDA    #$01
            STA    memTabl,X       ;Protect page $BF00
            DEX
            LDA    #$00            ;Clear the rest
:ClrLoop    STA    memTabl,X
            DEX
            BPL    :ClrLoop
            LDA    #%11001111
            STA    memTabl         ;Protect pages 0,1 & $400-$7FF (Screen)
Start       EQU    *

***************** See Rev Note #55 *********************

            JSR    HOME            ;Clear the screen
            JSR    CROUT
            LDX    #<Msg0-MsgStart ;Load offset to message into x...
            JSR    PrntLoop
            LDA    #3              ;Set CV to 3rd line
            STA    CV
            JSR    CROUT           ; & col 1
            JSR    GoPro           ;Call the MLI (Remember, this code executes at $1000)
            DB     $C7
            DA     Prefix
            LDX    pnBuf           ;Get PREFIX length
            LDA    #$00            ;Put a 0 at end of Prefix
            STA    pnBuf+1,X

******************* See Rev Note #69 *******************

            LDX    pnBuf           ;Get length byte back
            BEQ    NilPfx          ;Branch if no prefix to display!!!
:loop       LDA    pnBuf,X         ;Display prefix directly
            ORA    #$80            ;Set hi bit for NORMAL text
            STA    SLIN04-1,X      ; to the screen
            DEX
            BNE    :loop

NilPfx      LDX    #$00
            DEC    CV
            JSR    CROUT           ;Put the cursor on the first char
GetKey      JSR    RDKEY           ;Wait for keyboard input
            CMP    #$8D            ;Is it CR?
            BEQ    GotPfx          ;Yes, and we accept what was entered
            PHA                    ;No, save the char
            JSR    CLREOL          ;Clear rest of line
            PLA                    ;Get char back
            CMP    #$9B            ;Is it ESC?
            BEQ    Start           ;Yes, start over again
            CMP    #$98            ;If it is CTRL-X, start over
ReStrt      BEQ    Start           ;(Used as an extended BEQ from PRMPT)
            CMP    #$89            ;Is it TAB?
            BEQ    BadKey          ;No good if it is!
            CMP    #$FF            ;Delete?
            BEQ    :1              ;Branch if it is
            CMP    #$88            ;Back Space?
            BNE    NotBS
:1          CPX    #$00            ;If it is, are we at col 0?
            BEQ    *+5             ;If col 0, do nothing
            DEC    CH              ; else move left 1 char
            DEX                    ; decrement char count,
            JSR    CLREOL          ; clear rest of line
            JMP    GetKey          ;Go get another char

NotBS       BCS    Maybe
BadKey      JSR    BELL            ;Ring the speaker (bell) if it isn't
            JMP    GetKey

Maybe       CMP    #$DB            ;Ok, is it below 'Z'?
            BCC    *+4             ;Branch if yes
            AND    #$DF            ;If not, shift it up upper case
            CMP    #$AE            ;Is it below "."?
            BCC    BadKey          ;If yes, it ain't good!
            CMP    #$DB            ;Is it above "Z"?
            BCS    BadKey          ;If so, it also ain't good
            CMP    #$BA            ;Is it below ":"? ("." - "9" range)
            BCC    GoodKey         ;Yes, it's good!
            CMP    #$C1            ;If not, is it at or above "A"? ("A" - "Z")
            BCC    BadKey          ;No, reject it
GoodKey     INX                    ;It's OK.  Hallelulah!
            CPX    #39             ;Were there more than 39 chars?
            BCS    ReStrt          ;Yes, too many!  Go restart
            STA    pnBuf,X         ;No, save the lucky char
            JSR    COUT            ;Print it
            JMP    GetKey          ; & go get another

GotPfx      CPX    #$00            ;OK, is our Prefix length (chars entered)=0?
            BEQ    Prmpt           ;If yes, don't bother re-setting it
            STX    pnBuf           ;Set prefix length
            JSR    GoPro           ;Call the MLI
            DB     $C6
            DA     Prefix
            BCC    Prmpt           ;If ok, go get Filename
            JSR    BELL            ;If not, ring Bell
            LDA    #$00            ; & try again
BadPfx      BEQ    ReStrt          ;Z flag must be set for extended Branch

Prmpt       JSR    HOME            ;Clear the screen for application name
            JSR    CROUT           ;Output a CR
********************* Rev Note #55  *******************
            LDX    #<Msg-MsgStart  ; Load offset to message into x...
            JSR    PrntLoop
RetryRich   LDA    #$03            ;Set CV to 3rd line
            STA    CV
            JSR    CROUT           ; & col 1
            LDX    #$00

********************* Rev Note #69  *******************

Loop1       JSR    RDKEY
            CMP    #$9B            ;ESC
            BNE    NotEsc
            LDA    CH
            BNE    Prmpt
            BEQ    BadPfx          ;If ESC in col 0 go get PREFIX again
NotEsc      CMP    #$98            ;CTRL-X
ExtndBr     BEQ    Prmpt           ;(Used as a branch extender)
            CMP    #$89            ;TAB
            BEQ    NotGud
            CMP    #$FF            ;Delete?
            BEQ    :1
            CMP    #$88            ;BACK SPACE
            BNE    :2
:1          JMP    EatEm           ;Eat the previous character

:2          BCS    GetIn1          ;> $88 and the char may be acceptable
NotGud      JSR    BELL            ;Ring the bell (speaker)
            JMP    Loop1

GetIn1      CMP    #$8D            ;Is it a CR?
            BEQ    GetInpDone
            CMP    #$DB            ;> than "Z"
            BCC    *+4             ;No
            AND    #$DF            ;Make sure its Upper case
            CMP    #$AE            ;Is it "."?
            BCC    NotGud          ;Branch if less
            CMP    #$DB            ;Must be less than "["
            BCS    NotGud
            CMP    #$BA            ;OK if less than or equal to "9"
            BCC    ItsGud
            CMP    #$C1            ;Else must be > than "A"
            BCC    NotGud
ItsGud      PHA
            JSR    CLREOL
            PLA
            JSR    COUT            ;No, print it
            INX
            CPX    #39
            BCS    ExtndBr
            STA    pnBuf,X
            JMP    Loop1           ;Go get the next one

GetInpDone  LDA    #" "
            JSR    COUT            ;After the CR, blank out the cursor
            STX    pnBuf           ;Put the length in front of the name

*  At this point the specified Pathname is in pnBuf ($280)
*   and we can do a GET_FILE_INFO on it

            JSR    GoPro
            DB     $C4
            DA     Info
            BCC    InfoOK
            JMP    Error

InfoOK      LDA    Type
            CMP    #$FF            ;Is it a type SYS file?
            BEQ    DoIt
            LDA    #$01            ;Not SYS File
            JMP    Error

DoIt        LDA    #$00            ;It's a type SYS all right!
            STA    ClsNum
            JSR    GoPro
            DB     $CC
            DA     Cls             ;CLOSE all open files first
            BCC    ChkAcs
            JMP    Error

*  Now check for the proper access

ChkAcs      LDA    Acess           ;Get the allowed access
            AND    #readEnable     ;Is READ disabled?
            BNE    :1              ;No. Access ok
            LDA    #drvrIOError    ;I/O error
            JMP    Error           ;Never returns!

:1          JSR    GoPro
            DB     $C8
            DA     Opn             ;OPEN it
            BCC    *+5
            JMP    Error

            LDA    RefNum
            STA    ReedNum         ;Spread REFNUM around
            STA    eofNum

*  Ok it's OPEN, let's get the EOF

            JSR    GoPro
            DB     $D1
            DA     EOF
            BCS    Error
            LDA    eofB+2          ;3rd of 3 bytes
            BEQ    EOFOK
            LDA    #drvrIOError    ;I/O ERROR even though the
            BNE    Error           ; file is simply too large
EOFOK       LDA    eofB            ;Move EOF to Read # bytes
            STA    RCount
            LDA    eofB+1
            STA    RCount+1
            JSR    GoPro
            DB     $CA             ;Do the READ
            DA     Reed
            PHP                    ;Push the processor status
            JSR    GoPro
            DB     $CC             ;Close it
            DA     Cls
            BCC    *+6
            PLP                    ;Get status back (it is irrevalent now)
            BNE    Error           ;(if CLOSE generated an error)
            PLP                    ;We're here if CLOSE was OK
            BCS    *-4             ;JMP ERROR
            JMP    $2000

EatEm       LDA    CH              ;Is the cursor in col 0?
            BEQ    EatEmBak        ;Yes, ignore it
            DEX
            LDA    #" "
            JSR    COUT            ;Blank out the cursor
            DEC    CH              ;Point to last character
            DEC    CH              ; entered...
            JSR    COUT            ; and blank it too
            DEC    CH              ;Point to that location
EatEmBak    JMP    Loop1           ;Go back & get the next char

****************** See Rev Note #55  *****************

PrntLoop    LDA    Msg0,X          ;Display string; offset is in X.
            BEQ    :Ret            ;Branch if done.
            JSR    COUT            ;Output character...
            INX
            BNE    PrntLoop        ;Branch always.
:Ret        RTS

Error       STA    ErrNum
            LDA    #$0C            ;Put error message on line 13
            STA    CV
            JSR    CROUT
            LDA    ErrNum
            CMP    #badSystemCall
            BNE    NextErr
*************** See Rev Note #55  **************
            LDX    #<Err1-MsgStart ;Load x with offset to message
            BNE    DoError
NextErr     CMP    #badPathSyntax
            BEQ    Error3
            CMP    #pathNotFound
            BEQ    Error3
            CMP    #volNotFound
            BEQ    Error3
            CMP    #fileNotFound
            BEQ    Error3
            LDX    #<Err2-MsgStart ; Load x with offset to message
            BNE    DoError
Error3      LDX    #<Err3-MsgStart ;Load x with offset to message
DoError     JSR    PrntLoop
            JMP    RetryRich

*-------------------------------------------------
* Data

MsgStart    EQU    *
Msg0        ASC    "ENTER PREFIX (PRESS "A2"RETURN"A2" TO ACCEPT)"
            DB     $00
Msg         ASC    "ENTER PATHNAME OF NEXT APPLICATION"
            DB     $00
Err1        DB     $87
            ASC    "NOT A TYPE "A2"SYS"A2" FILE"
            DB     $00
Err2        DB     $87
            ASC    "I/O ERROR            "
            DB     $00
Err3        DB     $87
            ASC    "FILE/PATH NOT FOUND  "
            DB     $00

*

Info        DB     $0A             ;10 PARAMETERS ON GFI
            DA     pnBuf           ;Pathname buffer pointer
Acess       DB     $00             ;ACCESS
Type        DB     $00             ;File Type
            DS     $D,0            ;All the rest are unimportant

Opn         DB     $03             ;3 parameters on an OPEN
            DA     pnBuf
            DA     $1800           ;FCB Buffer
RefNum      DB     $00

Cls         DB     $01
ClsNum      DB     $00             ;REFERENCE #

Reed        DB     $04             ;4 Parameters for a READ
ReedNum     DB     $00
            DA     $2000           ;SYS files always load at $2000
RCount      DW     $0000
            DW     $0000

EOF         DB     $02
eofNum      DB     $00
eofB        DS     3,0             ;Three byte EOF

Prefix      DB     $01
            DA     pnBuf

ZZSiz       EQU    *-HereIn
ZZFre       EQU    $2FF-ZZSiz
            DS     $35,0