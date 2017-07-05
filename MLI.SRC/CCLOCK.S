***********************************************************
*
*       ProDOS 8 CORTLAND CLOCK DRIVER
*
*         COPYRIGHT APPLE COMPUTER, INC., 1986
*
*         ALL RIGHTS RESERVED
*
*       Written by Kerry Laidlaw, 2/12/86
*       Modified by Mike Askins, 9/6/86
*       Modified by Fern Bachman, 9/7/86
*
***********************************************************
*
* This is the ProDOS8 Cortland built-in clock driver.
* Its sole function in life is to fetch the time from the Cortland
* clock via the Read Hex Time misc. tool call, and transfer this
* time into the ProDOS global page time format.
*
* This routine will IGNORE any errors passed back to it from the
* Read Hex Time call.  This was done since existing ProDOS8 programs
* cannot deal with some new time error code.
* Thus the only way that a user can tell if his Cortland clock is
* broken, is by noticing that the date and time fields are zeroed.
*
* Note: There are some interesting facts to know regarding the
* slot clock driver for ProDOS8 and the built-in
* Cortland clock.  The year value returned from the Cortland clock
* is an offset from the year 1900.  Thus Cortland is capable of
* reporting the year correctly until 1900+255=2155.  Only 7 bits
* are used for the year in the ProDOS8 global page, so theoretically
* 1900+127=2027 is the last year that ProDOS could represent on a
* Cortland.  But this is only if the ProDOS8 year value is interpreted
* as being an offset from 1900.
*
* Historically, the year value has been interpreted as the binary
* representation of the last two digits of the year 19xx.
* So this means that programs that display the year as a concatenation
* of 19 and the ascii equivalent of the year value will work until 1999.
* And programs that just display the last two digits of the year will
* still work correctly until (20)27 if they convert the year value
* correctly, but ignore any hundredths place digit.
*
* Apple //e's that use slot clocks that utilize the slot clock
* driver have further restrictions of the year value.  The slot
* clock driver calculates the year given the position of the day
* of the week in the month.  This algorithm then uses a year look
* up table that has seven possible values.  Leap years are repeated
* in the table.  Since 1988 is a leap year, then the updated slot
* clock driver (file TCLOCK) will yield the six year offset values
* rather then seven.
* So before 1992, if ProDOS8 still exists, the slot clock driver
* routine must be updated again!
*
* So, we now have the following definition:
*    The value placed in the year field is defined as the
*    number of years past the year 1900.
*    Numerically speaking: Current Year = 1900 + year value.

            MX     %11

            ORG    ClockBegin

* This mod will force read/write main memory for the tool
* call by resetting the read/write auxillary memory bits
* in the state register (statereg).

            MX     %11
IIgsClock   EQU    *
            SEP    #$30            ;Make sure we're in 8 bit mode
            LDA    STATEREG        ;Get the state reg
            STA    SaveState       ;Keep for restore after tool call
            AND    #%11001111      ;Clear the Read/Write aux memory bits
            STA    STATEREG        ;Make it real

* First off, lets get into native mode with 16 bit m & x.

            MX     %00
            CLC                    ;Set e = 0, to set native mode
            XCE
            REP    #$30            ;Zero m & x for 16-bit mode
            LDA    #$0000          ;Zero out result space
            PHA                    ; Push 4 words for hex time result...
            PHA
            PHA
            PHA
            _ReadTimeHex

* Note that no error condition is checked for, so the date will
* be zeroed by default if an error indeed happened.
*
*  Back to 8 bit m to access results on stack...
            MX     %10
            SEP    #$20
            LDA    SaveState       ;Restore the state register
            STA    STATEREG

* Now let's pull the time off the stack and stick it in the global page.

            PLA                    ;Pull off Seconds, and ignore
            PLA                    ;Pull off Minutes
            STA    TimeLo          ;Store in global page
            PLA                    ;Pull off Hours
            STA    TimeLo+1        ;Store in global page
            PLA                    ;Pull off Year value

:loop1      CMP    #100            ;Adjust for
            BCC    :1
            SBC    #100            ; year 2000
            BRA    :loop1

:1          STA    DateLo+1        ; (year)
            PLA                    ;Pull off Day
            INC                    ;Increment day value for ProDOS8 format
            STA    DateLo          ;Store in global page
            PLA                    ;Pull off Month
            INC                    ;Incr month value for ProDOS8 format
            ASL                    ;Shift month as it sits in between
            ASL                    ; the year and day values
            ASL
            ASL
            ASL
            ORA    DateLo          ;Put all but the top bit of month value
            STA    DateLo          ; in the day byte
            ROL    DateLo+1        ;Put hi bit of mo. in lo bit of yr byte
            PLA                    ;Pull off unused byte
            PLA                    ;Pull off Day of Week. Stack now clean
            SEC                    ;Now go back to emulation mode
            XCE                    ; to continue with ProDOS8
            RTS                    ;That's all

SaveState   DB     $00             ;Keep the state of state register
            ASC    'JIMJAYKERRY&MIKE'
ClockEnd    EQU    *
            DS     125-ClockEnd+ClockBegin,0; Zero rest of 125 bytes
Size        EQU    *-ClockBegin    ;MUST be $7D (125) bytes in length!
            DS     $80-Size,0
