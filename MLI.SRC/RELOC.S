*******************************************************
* Program/data relocation routine is driven by a table
* describing program, vectors, and data segments. The
* table has the general format:
*  (1)command:     0= zero destinaton range.
*                  1= move data to from src to dst.
*                  2= high address ref tbl, relocate & move.
*                  3= lo-hi addr ref tbl, relocate & move.
*                  4= program, relocate & move.
*                 >4= end of table.
*  (2)dest addr:   address of where segment is to be moved.
*  (2)byte count:  length of segment.
*  (2)source addr: start address segment to be operated on,
*                  n/a if type=0, code does not have to be
*                  assembled at this address.
*  (1)segments:    number of address ranges to be tested
*                  and altered, n/a if type=0 or 1.
*                  limit and offset lists should each
*                  contain segments+1 (s) bytes.
*  (s)limitlow:    list of low page addresses to be tested.
*  (s)limithigh:   list of high page addresses to be tested.
*  (s)offset:      list of amounts to be added if
*                  low & high limits have been met.
*
* on entry: (X)=table address low, (Y)=table address high
* on exit:  carry clear if no error; else carry set,
*           (X)=addrLo, (Y)=addrHi of error causing source.
*           (A)=0 if input table error, =$ff if illegal opcode.
*******************************************************

Reloc       STX    relocTbl
            STY    relocTbl+1      ;Save address of control table
RelLoop     LDA    (relocTbl)      ;Get relocation command
            CMP    #$05            ;If 5 or greater then done...
            BCS    RelocEnd        ;Branch if done
            TAX
            LDY    #$01            ;Move destination address to
            LDA    (relocTbl),Y    ; zero page for indirect access
            STA    dst
            INY
            LDA    (relocTbl),Y
            STA    dst+1
            INY
            LDA    (relocTbl),Y    ;Also the length (byte count)
            STA    cnt             ; of the destination area
            INY
            LDA    (relocTbl),Y
            STA    cnt+1
            BMI    RelocErr        ;Branch if >=32K
            TXA                    ;Request to zero out destination?
            BEQ    Zero            ;Branch if it is
            INY
            LDA    (relocTbl),Y    ;Now get the source address
            STA    src
            STA    code            ;src is used for the move, 'code' is
            INY                    ; used for relocation
            CLC                    ;Add length to get final address
            ADC    cnt
            STA    endCode
            LDA    (relocTbl),Y
            STA    src+1
            STA    code+1
            ADC    cnt+1
            STA    endCode+1
            DEX                    ;Now that set-up is done, test for 'move'
            BEQ    MovEm           ;Branch if move only (no relocation)

            STX    wSize           ;Save element size (1,2,3)
            INY
            LDA    (relocTbl),Y    ;Now get the number of ranges
            STA    segCnt          ; that are valid relocation target addresses
            TAX                    ;Separate serial range groups into tables
RLimLo      INY                    ;Transfer low limits to 'limlo' table
            LDA    (relocTbl),Y
            STA    LimLo,X
            DEX
            BPL    RLimLo

            LDX    segCnt
RLimHi      INY
            LDA    (relocTbl),Y    ;Transfer high limits to 'limhi' table
            STA    LimHi,X
            DEX
            BPL    RLimHi

            LDX    segCnt
Rofset      INY
            LDA    (relocTbl),Y    ;Transfer offsets to 'ofset' table
            STA    Ofset,X
            DEX
            BPL    Rofset

            JSR    AdjTbl          ;Adjust 'relocTbl' to point at next spec
            LDX    wSize           ;Test for machine code relocation
            CPX    #$03
            BEQ    RelCode         ;Branch if program relocation

* 2/3 - Relocate addresses

            JSR    RelAdr          ;Otherwise, relocate addresses in
RelocEnd1   JSR    Move            ; one or two byte tables, then move to destination
            BRA    RelLoop         ;Do next table entry...
RelocEnd    CLC
            RTS
RelocErr    JMP    TblErr

*-------------------------------------------------
* 4 - Relocate instructions

RelCode     JSR    RelProg         ;Go relocate machine code references
            BRA    RelocEnd1

* 0 - Zero block

Zero        JSR    AdjTbl          ;Adjust 'relocTbl' pointer to next entry
            LDA    #$00            ;Fill destination range with zeros
            LDY    cnt+1           ;Is it at least a page?
            BEQ    ZPart           ;Branch if less than 256 bytes
            TAY
:ZeroLoop   STA    (dst),Y
            INY
            BNE    :ZeroLoop
            INC    dst+1           ;bump to next page
            DEC    cnt+1
            BNE    :ZeroLoop
ZPart       LDY    cnt             ;any bytes left to zero?
            BEQ    Zeroed          ;branch if not
            TAY
:loop       STA    (dst),Y
            INY
            CPY    cnt
            BCC    :loop
Zeroed      JMP    RelLoop

* 1 - Copy block

MovEm       JSR    AdjTbl
            BRA    RelocEnd1

*-------------------------------------------------
* Advance table ptr

AdjTbl      TYA                    ;Add previous table length to 'relocTbl'
            SEC                    ; to get position of next entry in table
            ADC    relocTbl
            STA    relocTbl
            BCC    :Rtn
            INC    relocTbl+1
:Rtn        RTS

*-------------------------------------------------

Move        LDA    src+1           ;Determine if move is up, down
            CMP    dst+1           ; or not at all
            BCC    MovUp           ;Branch if definitely up...
            BNE    MovDown         ;Branch if definitely down...
            LDA    src
            CMP    dst
            BCC    MovUp           ;Branch if definitely up...
            BNE    MovDown         ;Branch if definitely down...
            RTS                    ;Otherwise, don't move nuting

*-------------------------------------------------
* src addr < dest addr

MovUp       LDY    cnt+1           ;Calc highest page of move up
            TYA
            CLC
            ADC    src+1
            STA    src+1           ; & adjust src & dst accordingly
            TYA
            CLC
            ADC    dst+1
            STA    dst+1
            LDY    cnt             ;Move partial page first
            BEQ    :1              ;Branch if no partial pages
:MovLoop    DEY
            LDA    (src),Y
            STA    (dst),Y
            TYA                    ;End of page transfer?
            BNE    :MovLoop        ;No
:1          DEC    dst+1
            DEC    src+1
            DEC    cnt+1           ;Done with all pages?
            BPL    :MovLoop        ;Branch if not
            RTS

*-------------------------------------------------
* src addr > dest addr

MovDown     LDY    #$00
            LDA    cnt+1           ;Partial page move only?
            BEQ    :1              ;Branch if less than a page to be moved
:MovLoop1   LDA    (src),Y
            STA    (dst),Y
            INY
            BNE    :MovLoop1
            INC    dst+1           ;Bump addresses
            INC    src+1
            DEC    cnt+1           ;More pages?
            BNE    :MovLoop1       ;Branch if more pages
:1          LDA    cnt             ;Move partial page
            BEQ    :Rtn            ;Branch if no more to move
:MovLoop2   LDA    (src),Y
            STA    (dst),Y
            INY
            CPY    cnt
            BNE    :MovLoop2
:Rtn        RTS                    ;All done...

*-------------------------------------------------
* Address/page relocate

RelAdr      LDY    wSize           ;Determine 1 or 2 byte reference
            DEY
            LDA    (code),Y
            JSR    AdjAdr          ;Relocate reference
            LDA    wSize           ;Update and test 'code' pointer
            JSR    AdjCode
            BCC    RelAdr          ;Branch if more to do
            RTS

*-------------------------------------------------
* Instructions relocate

RelProg     LDY    #$00            ;Fetch next opcode
            LDA    (code),Y
            JSR    GetOpLen        ;Determine if it's a 3-byte instruction
            BEQ    RPerr           ;Branch if not an opcode
            CMP    #$03
            BNE    :1
            LDY    #$02
            JSR    AdjAdr          ;Relocate address
            LDA    #$03
:1          JSR    AdjCode         ;Update and test 'code' for done
            BCC    RelProg         ;Loop if more to do
            RTS

*-------------------------------------------------
* Error handling...

RPerr       PLA                    ;Return bad code address
            PLA                    ;First un-do stack
            LDX    code
            LDY    code+1
            LDA    #$FF            ;Indicate bad opcode
            SEC                    ;Indicate error
            RTS

*-------------------------------------------------
* Error return

TblErr      LDX    relocTbl        ;Return table address error
            LDY    relocTbl+1
            LDA    #$00            ;Indicate input table error
            SEC
            RTS

*-------------------------------------------------
* Relocate absolute addr

AdjAdr      LDA    (code),Y        ;Get page address
            LDX    segCnt          ; and test against limits
:AdjLoop    CMP    LimLo,X         ;Is it >= low?
            BCC    :Next           ;Branch if not
            CMP    LimHi,X         ;Is it =< highest page limit
            BCC    :1              ;Branch if it is
            BEQ    :1
:Next       DEX                    ;Try next limit set
            BPL    :AdjLoop
            RTS                    ;Teturn without adjustment

:1          CLC                    ;Add offset to form relocated
            ADC    Ofset,X         ; page address
            STA    (code),Y        ; & replace old address with result
            RTS

*-------------------------------------------------
* Bump ptr to next addr

AdjCode     CLC                    ;Update 'code' pointer
            ADC    code
            LDY    code+1
            BCC    :1              ;Branch if not page cross
            INY                    ;Update high order address too
:1          CPY    endCode+1       ;Has all code/data been processed?
            BCC    :2              ;Branch if definitely not
            CMP    endCode         ;If carry results set, end of code
:2          STA    code
            STY    code+1          ;Save updated values
            RTS                    ;Return result (carry set=done)

*-------------------------------------------------
* Compute instruction len

GetOpLen    PHA                    ;Form index to table and which 2-bit group
            AND    #$03            ;Low 2 bits specify group
            TAY
            PLA
            LSR                    ;Upper 6 bits specify byte in table
            LSR
            TAX
            LDA    OpCodeLen,X
NxtGroup    DEY                    ;Is opcode length in lowest 2 bits of A-reg?
            BMI    RtnLen          ;Branch if it is
            LSR
            LSR                    ;Shift to next group
            BNE    NxtGroup        ;If len=0 then error...
RtnLen      AND    #$03            ;Strip other garbage
            RTS                    ;If z-flag true, then error!!!

*-------------------------------------------------
* The following table contains the length of each
* machine instruction (in two-bit groups).

OpCodeLen   HEX    0928193C
            HEX    0A280D3C
            HEX    0B2A193F
            HEX    0A280D3C
            HEX    0928193F
            HEX    0A280D3C
            HEX    0928193F
            HEX    0A280D3C
            HEX    082A113F
            HEX    0A2A1D0C
            HEX    2A2A193F
            HEX    0A2A1D3F
            HEX    0A2A193F
            HEX    0A280D3C
            HEX    0A2A193F
            HEX    0A280D3C

*-------------------------------------------------
* Relocation Data

wSize       DB     $00
segCnt      DB     $00
LimLo       HEX    0000000000000000;Start of range pages
LimHi       HEX    0000000000000000;End of pages+1
Ofset       HEX    0000000000000000;Additive factors

*-------------------------------------------------
* Install an exit code
* The locations GSOS($E100A8) & GSOS2 ($E100B0)
* are patched if the boot OS is P8

GSPatches   PHP
            SEI
            CLC
            XCE
            REP    #$30
            PHB
            PHA
            PHA                    ;long result
            PushLong               #ZZSize ;size 16 bytes
            PushWord               #$3101 ;userID
            PushWord               #attrLocked+attrNoCross+attrNoSpec
            PHA
            PHA
            _NewHandle
            LDA    $01,S           ;Let handle remain on stack
            TAX                    ; since we need it later but
            LDA    $03,S           ; move a copy to (Y,X)
            TAY
            PushLong               #ExitPatch ; srcPtr
            PHY
            PHX                    ;destHndl
            PushLong               #ZZSize ;# of bytes to be copied
            _PtrToHand
            PLX                    ;Put 24 bits of the 32-bit
            PLB                    ; handle that was left on stack
            LDA    |$0001,X        ; deref
            TAY                    ;mid & hi-byte of 24-bit ptr
            LDA    |$0000,X        ; low 16-bit of 24-bit ptr
            AND    #$00FF          ; Mask off mid byte
            XBA                    ;Lobyte of ptr to Hi-byte in ACC
            ORA    #$005C          ;Add in JMPL inst
            STAL   GSOS2           ;$5C xx
            CLC
            ADC    #$000B          ; ADC[]
            STAL   GSOS
            TYA                    ; mid & hi byte of 24-bit ptr
            STAL   GSOS2+2         ;yy zz
            ADC    #$0000
            STAL   GSOS+2
            PLB                    ;Discard the rest of the handle
            PLB
            SEC
            XCE
            PLP
            RTS

*-------------------------------------------------
* Remove 3 words & adjust stack
* to return to caller

            MX     %00
ExitPatch   LDA    $01,S           ;RTL-1 addr
            STA    $07,S
            LDA    $02,S
            STA    $07+1,S
            PLA
            PLA
            PLA
            LDA    #$00FF
            SEC
            RTL
ZZSize      EQU    *-ExitPatch
            DS     $23,0