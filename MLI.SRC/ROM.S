            TTL    'lang. cd. irq, nmi, & reset'

***********************************************************
* This code is used when an  IRQ happens while the RAM
* at $D000-$FFFF is switched on (inside an MLI
* call, for example) if we have the "new style"
* monitor ROMs

            ORG    $FF9B

LanIrq      PHA
            LDA    Acc             ;Save ($45)
            STA    old45           ;Now put A-reg into loc $45
            PLA
            STA    Acc
            PLA                    ;Get status register from stack
            PHA                    ; (and restore it!)
            AND    #$10            ;Is it a break or interupt
            BNE    lBreak          ;Branch if break
            LDA    $D000           ;Get bankID
            EOR    #$D8            ;Is the system active? (CLD)
            BEQ    SysActv         ;Branch if it is
            LDA    #$FF            ;In $D000 bank 2
SysActv     STA    IntBankID       ;Update bank ID (=$00/$FF)
            STA    afBank
            LDA    #>aftIrq        ;Push fake "RTI" vector
            PHA                    ; with IRQ disabled
            LDA    #<aftIrq        ;Set up return address
            PHA
            LDA    #$04            ;Status reg w/int flag set
            PHA
lBreak      LDA    #>ROMIrq        ;Push ROM entry also
            PHA
            LDA    #<ROMIrq
            PHA
GoROM       STA    RDROM2          ;Switch to ROM (hits RTS immediately)

lReset      LDA    rReset+1
            PHA                    ;Since reset, Acc can be destroyed
            LDA    rReset
            PHA
            JMP    GoROM

rReset      DA     $FA62-1         ;Monitor reset-1

*-------------------------------------------------

fix45       STA    IntAReg         ;Preserve the Acc 
            LDA    old45
            STA    Acc
            LDA    LCBANK1
            LDA    LCBANK1         ;Switch RAM in for write & read
            LDA    afBank
            JMP    IrqXit0

* (Y)=0
            
ZeroPfxPtrs STY    NewPfxPtr       ;Fix AppleTalk PFI bug
            STY    PfixPtr         ;Flag not an active prefix
            RTS

*(A)=flag
            
SetPfxPtrs  STA    NewPfxPtr
            STA    PfixPtr
            RTS

            DA     NMI
            DA     lReset
IrqVect     DA     LanIrq
