************************************************************
*                                                          *
*            PRODOS 8 KERNEL 59.5K RAMDISK (REV-E)         *
*                                                          *
*            COPYRIGHT APPLE COMPUTER, INC., 1983-86       *
*                                                          *
*                     ALL RIGHTS RESERVED                  *
*                                                          *
************************************************************

* This module consist of 3 object files

            TTL    'EXTENDED 80 COL RAMDISK'

            ORG    EnterCard
            MX     %11
* After the main routine has determined that the command
* is ok, and the block to be read/written is within
* range, it tranfers control to this routine.  This routine
* remaps the block requested as follows:
*     Request blocks 0,1 :invalid
*                      2 :returns VDIR (card block 3)
*                      3 :returns bitmap (synthesized)
*                      4 :returns card block 0
*                $05-$5F :returns card blocks $05-$5F
*                $60-$67 :returns blocks $68-$7F in bank 1 of
*                           card's language card
*                $68-$7F :returns blocks $68-$7F in bank 2
*                           of card's language card
*
DoCmd       LDA    RD80COL         ;Read 80STORE
            PHA                    ;Save for later
            STA    CLR80COL        ;Turn off 80STORE

            LDX    #$04            ;Move the params for our use
:loop       LDA    $42,X           ;CMD,UNIT,BUFPTR,&BLOCK(lo)
            STA    tCmd,X          ;->tCmd,tUnit,R2L,R2,R1
            DEX
            BPL    :loop

            AND    FormatFlag      ;Format the volume first time
            BNE    doCommand       ; thru, or when requested

doFormat    LDX    blockNum        ;Save R1 during format
            LDA    #>VBlock1       ;Block to be cleared
            JSR    ClrBuf1         ;ClrBuf clears all buffers
            LDY    #$03            ;Format volume in 2 chunks
:loop1      LDA    VDir,Y
            STA    VBlock1+4,Y
            DEY
            BPL    :loop1

            LDA    #$FE            ;Set last block as unusable to protect vectors
            STA    BitMap+$F
            TYA                    ;Set bitmap bits to $FF
            LDY    #$0E            ;15 bytes to set
:loop2      STA    BitMap,Y
            DEY
            BNE    :loop2
            STY    BitMap          ;First byte=0

            LDY    #$07            ;Do other chunk
:loop3      LDA    Access,Y
            STA    VBlock1+34,Y
            DEY
            BPL    :loop3

            LDA    FormatFlag      ;If 0, set to FF
            BNE    DFX             ;else exitcard

            STY    FormatFlag      ;Y=FF, won't format next time
            STX    R1              ;restore R1

* Now use the requested block number to determine
* which routine performs the transfer

doCommand   ASL    R1              ;Block requested->page requested
            LDA    R1              ;Get page requested
            CMP    #$BF            ;In Language card?
            BCS    XferLC1         ;Yes, do it
            CMP    #$06            ;Bit map?
            BNE    :1
            JMP    TBMap           ;Yes, transfer bitmap
:1          JMP    TReg            ;else normal transfer

* When a block between $60 and $7F is requested, it must
* be spirited into/from the language card area of the
* 64K card. This requires a two-stage move: into the temp
* buffer and then to its real destination.

XferLC1     TAX                    ;Save R1 for later
            JSR    SetPtr          ;Get direction
            PHP                    ;Save direction
            BCS    LCwrt           ;It is a write
LCrd        TXA                    ;Get R1 back
            CMP    #$CF            ;Which bank is it in?
            BCS    XferLC2         ;In main bank
            ORA    #$10            ;In secondary bank
            BNE    XferLC          ;Branch always

XferLC2     STA    LCBANK2         ;Turn on main $D000
            STA    LCBANK2

XferLC      STA    R1              ;Restore R1
            LDA    R2H             ;Save R2 for later
            PHA
            LDX    R2L
            STA    SETALTZP        ;Now switch to other ZP
            LDA    #>ABuf          ;Set R2 to Abuf
            STA    R2H
            LDA    #<ABuf
            STA    R2L
            JSR    SetPtr
            TAY
:CpyLoop    LDA    (A1),Y          ;Move A1,A2 to A4,A3
            STA    (A4),Y
            LDA    (A2),Y
            STA    (A3),Y
            DEY
            BNE    :CpyLoop

            STA    SETSTDZP        ;Restore normal ZP
            STX    R2L
            PLA                    ;Restore R2
            STA    R2H
            PLP                    ;Get direction
DFX         BCS    XLCwrt          ;Write, done with move

            STA    LCBANK1         ;Now switch MLI part of LC in
            STA    LCBANK1
            JSR    BlockDo0        ;Read, transfer Abuf to main

XLCwrt      JMP    ExitCard

LCwrt       JSR    BlockDo0        ;Transfer main to Abuf
            JMP    LCrd            ;Transfer Abuf to Lang card

*-------------------------------------------------
* BLOCKDo transfers a block between main memory and the
*  64K card.  R1 contains the page address of the block
*  in the card; R2 contains the page address of the block
*  in main memory.  The address in main memory is always
*  in the language card, so the language card is always
*  switched in.  If CMD is 2, a write is done (R2->R1);
*  if CMD is 1, a read is done (R1->R2).

BlockDo0    LDA    #>ABuf          ;Set up R1 = Abuf
BlockDo1    STA    R1
BlockDo     JSR    SetPtr          ;set pointers
            BCS    BlockWrite      ;it's a write
            STA    WRMAINRAM       ;transfer buffer directly to main ram
            TAY                    ;0 left from SETPTR
:CpyLoop    LDA    (A1),Y          ;Transfer A1,A2 to A4,A3
            STA    (A4),Y
            LDA    (A2),Y
            STA    (A3),Y
            DEY
            BNE    :CpyLoop
            STA    WRCARDRAM       ;Back the way it was
DoneWrt     RTS                    ;MainWrt returns here

BlockWrite  LDA    #<MainWrt       ;Pointers set up
            STA    PassIt          ;Pass control to main ram
            LDA    #>MainWrt
            JMP    Ex1             ;Set PassIt+1 and transfer

*-------------------------------------------------
* SETPTR is used by other routines to set up
* pointers and to detect read or write.

SetPtr      LDA    tCmd            ;The rest depends on read
            LSR                    ;or write.  Which is it?
            BCS    CmdWrt          ;It's write

CmdRd       LDA    R2H             ;Get dest page
            STA    A4+1            ;1st dest page (MOVE)
            STA    A3+1            ;2nd dest page
            LDA    R2L             ;Low byte dest page
            STA    A4              ;1st dest page low
            STA    A3              ;2nd dest page low
            LDA    R1              ;Get source page
            STA    A1+1            ;1st source page
            STA    A2+1            ;2nd source page
            LDA    #$00            ;Source page aligned
            STA    A1              ;1st source page
            STA    A2              ;2nd source page
            BEQ    CmdBoth         ;Update second pages

CmdWrt      LDA    R2H             ;Get source page
            STA    A1+1            ;1st source page
            STA    A2+1            ;2nd source page
            LDA    R2L             ;Get source page low
            STA    A1              ;1st source page low
            STA    A2              ;2nd source page low
            LDA    R1              ;Get dest page
            STA    A4+1            ;1st dest page
            STA    A3+1            ;2nd dest page
            LDA    #$00            ;Dest page aligned
            STA    A4              ;1st dest page
            STA    A3              ;2nd dest page

CmdBoth     INC    A2+1            ;Update 2nd source page
            INC    A3+1            ;Update 2nd dest page
            RTS

*-------------------------------------------------
* TZIP is called if Blocks 0,1,4,5 are requested.
* On write it does nothing, on read, it returns 0's

TZip        JSR    ClrBuf0         ;Fill ABUF with 0's
            JSR    BlockDo         ;Transfer them 0's
            JMP    ExitCard        ; & return

*-------------------------------------------------
* ClrBuf fills the buffer indicated by R1 to 0's
* Should only be called on a read or format.

ClrBuf0     LDA    #>ABuf          ;ABUF is temp buffer
ClrBuf1     STA    R1              ;Assign to BLOCK
ClrBuf2     JSR    SetPtr          ;Set pointers
            TAY                    ;A set to 0 by setptr
:CpyLoop    STA    (A1),Y
            STA    (A2),Y
            DEY
            BNE    :CpyLoop
            RTS

*-------------------------------------------------
* TREG maps the requested block into the aux card
* so that 8K data files will be contiguous (the index
* blocks will not be placed within data).

TReg        CMP    #$04            ;page 4 = vdir
            BNE    :1              ;Not vdir, continue
            LDA    #$07            ;Else xfer block 7
            BNE    GoTimes2

***************** See Rev Note #43 ********************

:1          CMP    #$0F            ;If any page<f (<block 8) requested
            BCC    TZip            ; it is invalid

            LDX    #$00            ;X contains number of iterations
            LDA    blockNum        ;Use true block number
            CMP    #$5D            ;Beyond 8K blocks?
            BCC    TReg1           ;No, do normal
            SBC    #$50            ;else subtract offset
GoTimes2    JMP    Times2          ;and multiply by 2

* Determine which 8K chunk it is in, place in X;
* block offset into chunk goes into Y.

TReg1       SEC
            SBC    #$08            ;block = block -6
:loop       CMP    #$11            ;If <=17, done
            BCC    :3              ;Yup, got iteration
            SBC    #$11            ;else block =block -17
            INX                    ;Count iteration
            BPL    :loop           ;Branch always
            DB     $00             ;Just in case (CRASH!)

* If remainder is 1, it's an index block: start index
* blocks at $1000,$2000..$19FF)
*    If remainder is 0, it is first data block in 8K
* chunk.  Page is 32 + (16 * X).
*    Otherwise, it is some other data block.
* Page is 32 + (16 * X) + (2 * Y)

:3          TAY                    ;Remainder in Y
            CPY    #$01            ;Is it index block?
            BNE    :4              ;No
            TXA                    ;Index = 2*(8+X)
            CLC
            ADC    #$08
            BNE    Times2          ;Multiply by 2
:4          INX                    ;Need iteration+1
            TXA                    ;Page = 2 * (16 + 8X)
            ASL
            ASL
            ASL
            ASL
            STA    R1
            TYA                    ;Get offset into 8K chunk
            BEQ    :5              ;if 0, no offset
            DEY                    ;else offset = 2 * Y
            TYA
:5          CLC
            ADC    R1
Times2      ASL                    ;A=2*A
            JSR    BlockDo1        ;Store in R1 and xfer
            JMP    ExitCard        ; & return

*-------------------------------------------------
* When Block 3 is requested, the bitmap is returned.  The
* Real bitmap is only 16 bytes long (BITMAP); the rest of
* the block is synthesized.  The temporary buffer at $800
* is used to build/read a full size bitmap block.

TBMap       LDA    #>ABuf          ;Use temporary buffer as BLOCK
            STA    R1
            JSR    SetPtr          ;Set pointers/test read-write
            BCS    BitWrt          ;Its a write!

BitRd       JSR    ClrBuf2

            LDY    #$0F            ;Now put real bitmap there
:CpyLoop    LDA    BitMap,Y
            STA    (A1),Y
            DEY
            BPL    :CpyLoop
            JSR    BlockDo         ;Move temp buf to user buf
            JMP    ExitCard

BitWrt      JSR    BlockDo         ;move user buf to temp buf
            JSR    SetPtr          ;Set pointers
            LDY    #$0F            ;move temp buf to bitmap
:CpyLoop    LDA    (A4),Y          ;(pointer set by SETPTR)
            STA    BitMap,Y
            DEY
            BPL    :CpyLoop
            JMP    ExitCard

*-------------------------------------------------
FormatFlag  DB     $00             ;Not formatted yet

tCmd        DS     1,0             ;Command byte
tUnit       DS     1,0             ;Unit byte (Not used)
R2L         DS     1,0             ;Low byte of user buffer
R2H         DS     1,0             ;Hi byte of user buffer
R1          DS     1,0             ;Page requested

BitMap      EQU    *
            HEX    00FFFFFF        ;Blocks 0-7 used
            HEX    FFFFFFFF
            HEX    FFFFFFFF
            HEX    FFFFFFFE

VDir        EQU    *               ;Start of virt dir
TypeNameLen DB     $F3             ;Storage type F, namelength 3
            ASC    'RAM'
Access      DB     $C3             ;Destroy, Rename, Read enabled
            DB     $27             ;entry length
            DB     $0D             ;Entries/Blk
            DW     $0000           ;File Count
            DW     $0003           ;Map_Pointer=Block 3
            DB     $7F             ;Total_Blocks=128 blocks

*-------------------------------------------------

ExitCard    LDA    LCBANK1         ;Restore lang card
            LDA    LCBANK1
            PLA                    ;Get 80STORE
            BPL    Ex0             ;80STORE wasn't on
            STA    SET80COL
Ex0         JMP    $03EF           ;Jump around PassIt (3ED,3EE)

            DS     $3EF-*,0        ;Pad thru $3EE

            LDA    #<NoErr         ;Set up return to NoErr
            STA    PassIt
            LDA    #>NoErr

Ex1         STA    PassIt+1        ;Also used by BlockWrite
            CLC                    ;Transfer card to main
            CLV                    ;Use standard zp/stk
            JMP    Xfer            ;There's no place like home...

*  NOTE: The previous section of code MUST NOT use $3FE & $3FF
*        since the Interrupt Vector must go there if AUX interrupts
*        are to be used.

            DS     2,0             ;Pad to end of mem page
