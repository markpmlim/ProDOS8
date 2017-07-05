**************************************************
            ORG    Srce
            MX     %11

* Move LCSrc to LCDest

            LDY    #$99            ;Move $9A bytes
:MovLoop    LDA    LCSrc,Y         ;Get a byte of source
            STA    LCDest,Y
            DEY
            CPY    #$FF
            BNE    :MovLoop

* Move RAMSrc to RAMDest

            LDX    #<RAMsrc
            STX    A1              ;Source low
            DEX                    ;Source end low
            STX    A2
            LDX    #>RAMsrc        ;Source high
            STX    A1+1
            INX
            STX    A2+1            ;End high
            LDA    #<RAMdest
            STA    A4
            LDA    #>RAMdest
            STA    A4+1
            SEC                    ;RAM to Card
            JSR    AuxMove         ;Use built-in rtn to move

* Now install it into the system

            LDA    #<LCdest        ;Put LC address into
            STA    DevAdr32        ; Slot 3, drive 2
            LDA    #>LCdest
            STA    DevAdr32+1
            INC    DevCnt
            LDX    DevCnt
            LDA    #%10110000+$F   ;Unit # of /RAM ($B0+$F)
            STA    DevLst,X        ;NB. $B0 ($30+hi-bit set)
            RTS

            DS     \,0             ;Pad to end of mem page