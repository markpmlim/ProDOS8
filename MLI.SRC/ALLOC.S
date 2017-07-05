**************************************************
* Free a blk on disk

Dealloc     STX    bmCnt           ;Save high order address of block to be freed
            PHA                    ;Save it
            LDX    vcbPtr          ; while the bitmap
            LDA    vcb+vcbTotBlks+1,X; disk address is checked
            CMP    bmCnt           ; to see if it makes sense
            PLA                    ;Restore
            BCC    DeAllocErr1     ;Branch if impossible

            TAX
            AND    #$07            ;Get the bit to be OR-ed in
            TAY
            LDA    WhichBit,Y      ;(shifting takes 7 bytes, but is slower)
            STA    noFree          ;Save bit pattern
            TXA                    ;Get low block address again
            LSR    bmCnt
            ROR                    ;Get pointer to byte in bitmap that
            LSR    bmCnt           ; represents the block address
            ROR
            LSR    bmCnt
            ROR
            STA    bmPtr           ;Save pointer
            LSR    bmCnt           ;Now transfer bit which specifies which page of bitmap
            ROL    half

            JSR    FindBitMap      ;Make absolutely sure we've got the right device
            BCS    DeAllocErr      ;Return any errors

            LDA    bmaCurrMap      ;What is the current map?
            CMP    bmCnt           ;Is in-core bit map the one we want?
            BEQ    :1              ;Branch if in-core is correct

            JSR    UpdateBitMap    ;Put current map away
            BCS    DeAllocErr      ;Pass back any error

            LDA    bmCnt           ;Get desired map number
            LDX    vcbPtr
            STA    vcb+vcbCurrBitMap,X
            LDA    bmaDev
            JSR    GetBitMap       ;Read it into the buffer
            BCS    DeAllocErr

:1          LDY    bmPtr           ;Index to byte
            LSR    half
            LDA    noFree          ;(get individual bit)
            BCC    bmBufHi         ;Branch if on page one of bitmap
            ORA    bmBuf+$100,Y
            STA    bmBuf+$100,Y
            BCS    DeAloc3         ;Branch always taken

bmBufHi     ORA    bmBuf,Y
            STA    bmBuf,Y

DeAloc3     LDA    #$80            ;mark bitmap as modified
            TSB    bmaStat
            INC    deBlock         ;Bump count of blocks deallocated
            BNE    :11
            INC    deBlock+1
:11         CLC
DeAllocErr  RTS

DeAllocErr1 LDA    #damagedBitMap  ;bit map block # impossible
            SEC                    ;Say bit map disk address wrong
            RTS                    ;(probably data masquerading as index block)

**************************************************
* Find a free disk block & allocate it
* Exit
*  (Y,A)=disk addr
*  (scrtch)=disk addr

Alloc1Blk   JSR    FindBitMap      ;Get address of bit map in 'bmAdr'
            BCS    ErrAloc1        ;Branch if error encountered
SrchFree    LDY    #$00            ;Start search at beginning of bit map block
            STY    half            ;Indicate which half (page) we're searching
GetBits1    LDA    bmBuf,Y         ;Free blocks are indicated by 'on' bits
            BNE    BitFound
            INY
            BNE    GetBits1        ;Check all of 'em in first page

            INC    half            ;Indicate search has progressed to page 2
            INC    basVal          ;base value=base address/2048
:loop       LDA    bmBuf+$100,Y    ;Search second half for free block
            BNE    BitFound
            INY
            BNE    :loop

            INC    basVal          ;Add 2048 offset for next page
            JSR    NxtBitMap       ;Get next bitmap (if it exists) and update VCB
            BCC    SrchFree        ;Branch if no error encountered
ErrAloc1    RTS                    ;Return error

* Calculate blk # represented by first set VBM bit

BitFound    STY    bmPtr           ;Save index pointer to valid bit group
            LDA    basVal          ;Set up for block address calculation
            STA    scrtch+1
            TYA                    ;Get address of bit pattern
            ASL                    ;Multiply this and basVal by 8
            ROL    scrtch+1
            ASL
            ROL    scrtch+1
            ASL
            ROL    scrtch+1
            TAX                    ;Now X=low address within 7 of actual address
            SEC
            LDA    half
            BEQ    Page1Alloc      ;Branch if allocating from 1st half
            LDA    bmBuf+$100,Y    ;Get pattern from second page
            BCS    adcAloc         ;Branch always
Page1Alloc  LDA    bmBuf,Y         ;Get bit pattern from first page 

adcAloc     ROL                    ;Find left most 'on' bit
            BCS    Bounce          ;Branch if found
            INX                    ;Adjust low address
            BNE    adcAloc         ;Branch always

Bounce      LSR                    ;Restore all but left most bit to original position
            BCC    Bounce          ;Loop until mark (set above) moves into Carry
            STX    scrtch          ;Save low address
            LDX    half            ;Which half of bit map?
            BNE    Page2Alloc
            STA    bmBuf,Y
            BEQ    DirtyBitMap     ;Branch always
Page2Alloc  STA    bmBuf+$100,Y    ;Update bitmap to show allocated block in use

DirtyBitMap LDA    #$80            ;Indicate map has been
            TSB    bmaStat         ; modified by setting dirty bit
            LDY    vcbPtr          ;Subtract 1 from total free
            LDA    vcb+vcbFreeBlks,Y; blocks in VCB to account for newly
            SBC    #$01            ; allocated block (carry is set from 'bounce')
            STA    vcb+vcbFreeBlks,Y
            BCS    Ret1Blk         ;Branch if hi free count doesn't need adjustment

            LDA    vcb+vcbFreeBlks+1,Y;Adjust high count
            DEC
            STA    vcb+vcbFreeBlks+1,Y
Ret1Blk     CLC                    ;Indicate no error encountered
            LDA    scrtch          ;Get address low in A-Reg
            LDY    scrtch+1        ; & high address in Y-Reg
            RTS                    ;Return address of newly allocated block

*-------------------------------------------------
* Get next volume bit map block

NxtBitMap   LDY    vcbPtr          ;Before bumping to next map,
            LDA    vcb+vcbTotBlks+1,Y; check to be sure there is
            LSR                    ; indeed a next map!
            LSR
            LSR
            LSR
            CMP    vcb+vcbCurrBitMap,Y;Are there more maps?
            BEQ    NoMorBM         ;Branch if no more to look at
            LDA    vcb+vcbCurrBitMap,Y
            INC                    ;Add 1 to current map
            STA    vcb+vcbCurrBitMap,Y
            JSR    UpdateBitMap

*-------------------------------------------------
* Read volume bit map block

FindBitMap  LDY    vcbPtr          ;Get device number
            LDA    vcb+vcbDevice,Y
            CMP    bmaDev
            BEQ    FreshMap
            JSR    UpdateBitMap    ;Save out other volumes' bitmap, and
            BCS    NoGo

            LDY    vcbPtr
            LDA    vcb+vcbDevice,Y
            STA    bmaDev          ; read in fresh bitmap for this device
FreshMap    LDY    bmaStat         ;Is this one already modified?
            BMI    BMFound         ;Yes, return pointer in 'bmAdr'
            JSR    GetBitMap       ;Otherwise read in fresh bit map
            BCS    NoGo            ;Branch if unsuccessful

BMFound     LDY    vcbPtr
            LDA    vcb+vcbCurrBitMap,Y;Get offset into VBM
            ASL
            STA    basVal          ;Save page offset into VBM
            CLC                    ;Indicate all is valid and good!
NoGo        RTS

NoMorBM     LDA    #volumeFull     ;Indicate request can't be filled
            SEC                    ;Indicate error
            RTS

*-------------------------------------------------
* Check point vol bitMap for disk writing

UpdateBitMap       CLC             ;Anticipate nothing to do
            LDA    bmaStat         ;Is current map dirty?
            BPL    NoGo            ;No need to do anything
            JSR    WrtBitMap       ;It is dirty, update device! 
            BCS    NoGo            ;Error encountered on writing
            LDA    #$00
            STA    bmaStat         ;Mark bm buffer as free
            RTS                    ;All done!

*-------------------------------------------------
* Prepare to read Vol BitMap block

GetBitMap   STA    bmaDev          ;Read bitmap specified by dev & vcb
            LDY    vcbPtr          ;Get lowest map number with free blocks in it
            LDA    vcb+vcbCurrBitMap,Y
            STA    bmaCurrMap      ;Associate the offset with the bitmap control block

            CLC                    ;Add this number to the base
            ADC    vcb+vcbBitMap,Y ; address of first bit map
            STA    bmaDskAdr       ;Save low address of bit map to be used
            LDA    vcb+vcbBitMap+1,Y;Now get high disk address of map
            ADC    #$00            ;Add to this the state of the carry
            STA    bmaDskAdr+1     ;Save high disk address too
            LDA    #rdCmd

* Read/write Volume BitMap block

DoBMap      STA    dhpCmd          ;Save device command
            LDA    DevNum          ;Preserve current devnum.
            PHA
            LDA    bmaDev          ;Get bitmap's device number
            STA    DevNum

            LDA    bmaDskAdr       ; & map's disk address
            STA    blockNum
            LDA    bmaDskAdr+1
            STA    blockNum+1

            LDA    bmBufHi+2
            JSR    DoBitMap        ;(note: low address is fixed to zero as this is a buffer)
            TAX                    ;Preserve error code, if any
            PLA                    ;Restore the
            STA    DevNum          ; dev # we came in with!
            BCC    :Ret            ;Return devnum if no error
            TXA                    ;Return any errors
:Ret        RTS

*-------------------------------------------------
* Read blk # in A,X regs

RdBlkAX     STA    blockNum
            STX    blockNum+1
            JSR    RdGBuf
            RTS

*-------------------------------------------------
* Write Vol BitMap block

WrtBitMap   LDA    #wrtCmd         ;write bit map
            BNE    DoBMap          ;Branch always 

* Write primary buffer blk

WrtGBuf     LDA    #wrtCmd         ;Set call for write
            BNE    SavGCmd         ;Branch always

* Read primary buffer blk

RdGBuf      LDA    #rdCmd          ;Set call for read

* Read/Write primary buffer blk

SavGCmd     STA    dhpCmd          ;Passed to device handler
            LDA    #>genBuf        ;Get high address of general buffer

*-------------------------------------------------
* Read/Write block

DoBitMap    PHP                    ;No interupts allowed
            SEI
            STA    bufPtr+1        ;General purpose buffers always
            STZ    bufPtr          ; start on a page boundary
            STZ    SErr            ;Clear global error value

            LDA    #$FF            ;Also, set to indicate
            STA    ioAccess        ; reg call made to dev handler
            LDA    DevNum          ;transfer the device number for
            STA    unitNum         ; dispatcher to convert to unit number.
            JSR    DMgr            ;Call the driver
            BCS    :1              ;Branch if error
            PLP                    ;Restore interupts
            CLC
            RTS

:1          PLP                    ;Restore interupts
            SEC
            RTS