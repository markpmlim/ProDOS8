***********************************************************
*                                                         *
*          PRODOS 8 CLOCK DRIVER INTERFACE ROUTINE        *
*                                                         *
*           COPYRIGHT APPLE COMPUTER, INC., 1983-86       *
*                                                         *
*                    ALL RIGHTS RESERVED                  *
*                                                         *
***********************************************************
            DUM    $3A
TENS        EQU    *               ;NO CONFLICT SINCE MONTH IS LAST PROCESSED.
MONTH       DS     1
WKDAY       DS     1
DAY         DS     1
HOUR        DS     1
MINUTE      DS     1
            DEND

WrtTCP      EQU    $C10B
RdTCP       EQU    $C108           ;CLOCK READ ENTRY POINTS
ClkMode     EQU    $0538           ;(+$CN=$5F8+N)

            ORG    ClockBegin

ReadClk     LDX    ClkSlt          ;PRESERVE CURRENT MODE FOR THUNDERCLOCK
            LDA    ClkMode,X
            PHA
            LDA    #$A3            ;SEND NUMERIC MODE BYTE TO THUNDERCLOCK
            JSR    WrtTCP
ClkSlt      EQU    *+2
            JSR    RdTCP           ;READ MONTH, DAY OF WEEK, DAY OF MONTH
            CLC                    ; AND TIME INTO INPUT BUFFER
            LDX    #$04            ;INDEX FOR 5 VALUES
            LDY    #$0C            ;READ MINUTES FIRST, MONTH LAST
Convrt      LDA    inBuf,Y         ;CONVERT VALUES TO BINAR
            AND    #$07            ;NO VALUE > 5 DECIMAL
            STA    TENS            ;MULTIPLY 'TENS' PLACE VALUE
            ASL
            ASL
            ADC    TENS            ;NOW IT'S TIMES 5
            ASL                    ;NOW IT IS TIMES 10!
            ADC    inBuf+1,Y       ;ADD TO ASCII 'ONES' PLACE
            SEC                    ;AND SUBTRACT OUT THE ASCII...
            SBC    #"0"
            STA    MONTH,X         ;SAVE CONVERTED VALUE
            DEY                    ;INDEX TO NEXT LOWER VALUE
            DEY
            DEY
            DEX                    ;ARE THERE MORE VALUES?
            BPL    Convrt          ;BRANCH IF THERE ARE

            TAY                    ;A STILL CONTAINS MONTH, SAVE IN Y FOR NOW
            LSR
            ROR
            ROR
            ROR                    ;(HI BIT OF MONTH HELD IN CARRY)
            ORA    DAY
            STA    DateLo          ;SAVE LOW VALUE OF DATE
            PHP                    ;SAVE HI BIT OF MONTH FOR NOW
            AND    #$1F            ;ISOLATE DAY AGAIN
                                   ; (WHEN MONTH >7 CARRY SET ACCOUNTED FOR IN FOLLOWING ADD)
            ADC    TDays-1,Y       ;REMEMBER THAT Y=MONTH
            BCC    :1              ;BRANCH NOT SEPT 13 THRU 30
            ADC    #$03            ;ADJUST FOR MOD 7 WHEN DAY > 256
:1          SEC
:loop       SBC    #$07
            BCS    :loop           ;LOOP UNTIL LESS THAN 0
            ADC    #$07            ;NOW MAKE IT IN THE RANGE OF 0-6
            SBC    WKDAY           ; THE DELTA PROVIDES YEARS OFFSET
            BCS    :2              ;BRANCH IF POSITIVE
            ADC    #$07            ;ELSE MAKE IT POSITIVE AGAIN
:2          TAY                    ;LOOK UP YEAR!
            LDA    YrAdj,Y
            PLP                    ;LASTLY, COMBINE WITH HI BIT OF MONTH
            ROL
            STA    DateLo+1        ;AND SAVE IT
            LDA    HOUR
            STA    TimeLo+1        ;MOVE HOUR AND MINUTE TO PRODOS GLOBALS
            LDA    MINUTE
            STA    TimeLo
            PLA
            LDX    ClkSlt          ;RESTORE PREVIOUS MODE
            STA    ClkMode,X
            RTS                    ;ALL DONE...

TDays       HEX    001F3B5A
            HEX    7897B5D3
            HEX    F2143351

YrAdj       HEX    605F5E5D
            HEX    626160
            DS     $80-$7D,0