**************************************************
* Ram Disk function Handler

            ORG    LCDest
            MX     %11
EnterRAM    CLD                    ;/RAM entry point
            LDX    #12-1           ;Save 12 bytes of params
:CpyLoop1   LDA    A1,X
            STA    A1L1,X
            DEX
            BPL    :CpyLoop1

            LDX    #1              ;Save XFER Vectors too 
:CpyLoop2   LDA    PassIt,X
            STA    SP1,X
            DEX
            BPL    :CpyLoop2

            LDA    dhpCmd          ;Get command
            BEQ    STAT            ;0=STATUS
            CMP    #$04            ;Check for command too high
            BCS    IOErr           ;If it is, IO ERR
            EOR    #$03            ;0=FORMAT,2=READ,1=WRITE
            STA    $42             ;CMD=>0=Format,2=Read,1=Write
            BEQ    Format          ;Format the volume

            LDY    blockNum+1      ;Check for enormous blocknum
            BNE    IOErr           ;I/O error if too big
            LDA    blockNum
            BMI    IOErr           ;Largest block is $7F

* At this point, control is passed to the code in the
* alternate 64K.  It is used for read, write, and 
* format.  After the request is completed, control
* is always passed back to NoErr.

Format      LDA    #<EnterCard     ;Card entry point
            STA    PassIt          ;Figure it out on card
            LDA    #>EnterCard
GoCard      STA    PassIt+1        ;Also used by MainWrt 
            SEC                    ;RAM->Card
            CLV                    ;start with original z.p.
            JMP    Xfer            ;transfer control

IOErr       LDA    #drvrIOError    ;Get err num
            BNE    ErrOut          ; & return (always)

WPErr       LDA    #drvrWrtProt
ErrOut      SEC                    ;Flag error
            BCS    Restore         ;Restore cmd and unitnum

STAT        EQU    *
NoErr       LDA    #$00            ;No error
            CLC                    ;Flag no error

Restore     PHP                    ;Save status
            PHA                    ;Save error code

            LDX    #12-1           ;Restore 12 bytes of params
:CpyLoop    LDA    A1L1,X
            STA    A1,X
            DEX
            BPL    :CpyLoop

            LDA    SP1             ;Restore XFER params
            BIT    $6060           ;This instruction is to put
            STA    PassIt          ; an RTS at $FF58 as in ROM
            LDA    SP1+1
            STA    PassIt+1

* -------------------- See rev note 21 -----------------------

            PLA                    ;Get error
            PLP                    ;Get status
            RTS

*-------------------------------------------------
* Write file buffer in MAIN to AUX block
* Assume A1,A2,A3,A4 ptrs are set in Aux Driver

MainWrt     STA    WRCARDRAM       ;Xfer data to card
            LDY    #$00
:MovLoop    LDA    (A1),Y          ;Pointers set in card by SETPTR
            STA    (A4),Y
            LDA    (A2),Y
            STA    (A3),Y
            DEY
            BNE    :MovLoop
            STA    WRMAINRAM       ;Done writing Card

            LDA    #<DoneWrt
            STA    PassIt
            LDA    #>DoneWrt
            JMP    GoCard

SP1         DS     2,0
A1L1        DS     12,0            ;12 bytes of storage
            DS     11,0            ;Pad to int handler