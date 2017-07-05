**************************************************
* "DeTree" deallocates blocks from tree files.
*
* It is assumed that the device preselected and the 'genBuf' may be used.
*
* On entry the following values must be set:
*   storType = storage type in upper nibble, lower nibble is undisturbed.
*   firstBlkL & firstBlkH = first block of file (index or data)
*   deBlock = 0 (see below)
*   dTree = ptr to 1st block with stuff to be deallocated at tree level.
*   dSap = ptr to 1st block at sapling level
*   dSeed = byte (0-511) position to be zeroed from (inclusive).
* NB. There is 2 special cases when dSeed = 512
* Case 1) when EOF is set at a block boundary
* Case 2) when file is destroyed
*
* On exit:
*   storType = modified result of storage type (if applicable)
*   firstBlkL & H = modified if storage type changed.
*   deBlock = total number of blocks freed at all levels.
*   dTree, dSap, dSeed unchanged.
*
* To trim a tree to a seed file, both dTree and dSap must be zero.
* To go from tree to sapling, dTree alone must be zero.

DeTree      LDA    storType        ;Which flavor of tree?
            CMP    #sapling*16     ;Is it a 'seed' (<=$1F)
            BCC    SeedDeAlloc     ;Yes
            CMP    #tree*16        ;Maybe a 'sapling'?
            BCC    SapDeAlloc
            CMP    #{tree+1}*16    ;Well, at least be certain it's a 'tree'
            BCC    TreeDeAlloc     ;Branch if it is
            LDA    #badBlockErr    ;Block allocation error
            JSR    SysDeath        ;Should never have been called

SeedDeAlloc LDA    dSap
            ORA    dTree
            BNE    BummErr
            JMP    SeedDeAlloc0    ;Trim to a seed

SapDeAlloc  LDA    dTree
            BNE    BummErr
            JMP    SapDeAlloc0     ;Trim to a sapling

TreeDeAlloc LDA    #128
            STA    topDest         ;For tree top, start at end, work backwards
:loop1      JSR    RdKeyBlk        ;Read specified first block into genBuf
            BCS    BummErr         ;Return all errors
            LDY    topDest         ;Get current pointer to top indexes
            CPY    dTree           ;Have enough sapling indexes been deallocated?
            BEQ    TreeDel17       ;Yes, now deallocate top guys!

            LDX    #$07            ;Buffer up to 8 sapling index block addrs
:loop2      LDA    genBuf,Y        ;Fetch low block address
            STA    deAlocBufL,X    ; and save it
            ORA    genBuf+$100,Y   ;Is it a real block that is allocated?
            BEQ    :1              ;It's a phantom block
            LDA    genBuf+$100,Y   ;Fetch hi block addr
            STA    deAlocBufH,X    ; and save it
            DEX                    ;Decrement and test for dealoc buf filled
            BMI    :2              ;Branch if we've fetched 8 addresses
:1          DEY                    ;Look now for end of deallocation limit
            CPY    dTree           ;Is this the last position on tree level?
            BNE    :loop2          ;No

            INY
            LDA    #$00            ;Fill rest of deAloc buffer with NULL addresses
:loop3      STA    deAlocBufL,X
            STA    deAlocBufH,X
            DEX
            BPL    :loop3          ;Loop until filled

:2          DEY                    ;Decrement to prepare for next time
            STY    topDest         ;save index

            LDX    #$07
:loop4      STX    dTempX          ;Save index to deAloc buf
            LDA    deAlocBufL,X
            STA    blockNum
            ORA    deAlocBufH,X    ;Are we finished?
            BEQ    :loop1          ;Branch if done with this level

            LDA    deAlocBufH,X    ;Complete address with hi byte
            STA    blockNum+1
            JSR    RdGBuf          ;Read sapling level into genBuf
            BCS    BummErr         ;Return any errors
            JSR    DeAllocBlk      ;Go free all data indexes in this block
            BCS    BummErr
            JSR    WrtGBuf
            BCS    BummErr
            LDX    dTempX          ;Restore index to dealloc buff
            DEX                    ;Are there more to free?
            BPL    :loop4          ;Branch if there are
            BMI    :loop1          ;Branch always to do next bunch

deAlocTreeDone     EQU             *
deAlocSapDone      EQU             *
BummErr     RTS

TreeDel17   LDY    dTree           ;Now deallocate all tree level
            INY                    ; blocks greater than specified block
            JSR    DeAlocBlkZ      ;(tree top in genBuf)
            BCS    BummErr         ;Report any errors
            JSR    WrtGBuf         ;Write updated top back to disk
            BCS    BummErr
            LDY    dTree           ;Now figure out if tree can become sapling
            BEQ    :11             ;Branch if it can!

            LDA    genBuf,Y        ;Otherwise, continue with partial
            STA    blockNum        ; deallocation of last sapling index
            ORA    genBuf+$100,Y   ;Is there such a sapling index block?
            BEQ    deAlocTreeDone  ;All done if not!
            LDA    genBuf+$100,Y   ;Read in sapling level to be modified
            STA    blockNum+1
            JSR    RdGBuf          ;Read 'highest' sapling index into genBuf
            BCC    SapDeAllocZ
            RTS

:11         JSR    Shrink          ;Shrink tree to sapling
            BCS    BummErr

* Deallocate a sapling file

SapDeAlloc0 JSR    RdKeyBlk        ;Read specified only sapling level index into gbuf
            BCS    BummErr
SapDeAllocZ LDY    dSap            ;fetch pointer to last of desirable indexes
            INY                    ;Bump to the first undesirable
            BEQ    :21             ;branch if all are desirable
            JSR    DeAlocBlkZ      ;Deallocate all indexes above appointed
            BCS    BummErr
            JSR    WrtGBuf         ;Update disk with remaining indexes
            BCS    BummErr

:21         LDY    dSap            ;Now prepare to cleanup last data block
            BEQ    :22             ;Branch if there is a posiblity of making it a seed
:loop       LDA    genBuf,Y        ;Fetch low order data block addr
            STA    blockNum
            ORA    genBuf+$100,Y   ;Is it a real block?
            BEQ    deAlocSapDone   ;We're done if not
            LDA    genBuf+$100,Y
            STA    blockNum+1
            JSR    RdGBuf          ;Go read data block into gbuf
            BCC    SeedDeAllocZ    ;Branch if good read
            RTS                    ;Otherwise return error

:22         LDA    dTree           ;Are both tree and sap levels zero?
            BNE    :loop           ;Branch if not.
            JSR    Shrink          ;Reduce this sap to a seed
            BCS    BumErr1

* If no error, drop into SeedDeAlloc0

SeedDeAlloc0       JSR             RdKeyBlk ;Go read only data block
            BCS    BumErr1         ;Report any errors
SeedDeAllocZ       LDY             dSeed+1 ;Check hi byte for no deletion
            BEQ    :31             ;Branch if all of second page is to be deleted
            DEY                    ;If dseed>$200 then were all done!
            BNE    BumErr1         ;Branch if that's the case

            LDY    dSeed           ;Clear only bytes >= dseed
:31         LDA    #$00
:loop1      STA    genBuf+$100,Y   ;Zero out unwanted data
            INY
            BNE    :loop1
            LDY    dSeed+1         ;Was that all?
            BNE    :32             ;Branch if it was
            LDY    dSeed
:loop2      STA    genBuf,Y
            INY
            BNE    :loop2
:32         JMP    WrtGBuf         ;Update data block to disk
BumErr1     RTS

RdKeyBlk    LDA    firstBlkL       ;Read specified first
            LDX    firstBlkH       ; block into genBbuf
            JMP    RdBlkAX         ;Go do it!

**************************************************
* Beware that dealloc may bring in a new bitmap block
* and may destroy locations 46 and 47 which use to
* point to the current index block.
**************************************************
Shrink      LDX    firstBlkH       ;First deallocate top block
            TXA
            PHA
            LDA    firstBlkL
            PHA                    ;Save block address of this index block
            JSR    Dealloc         ;Go do it
            PLA
            STA    blockNum        ;Set master of sapling index block address
            PLA
            STA    blockNum+1
            BCS    :Ret            ;report any errors

            LDA    genBuf          ;Get first block at lower level
            STA    firstBlkL
            LDA    genBuf+$100
            STA    firstBlkH
            LDY    #$00
            JSR    SwapMe
            SEC                    ;Now change file type, from
            LDA    storType        ; tree to sapling,
            SBC    #$10            ; or from sapling to seed!
            STA    storType
            JSR    WrtGBuf
:Ret        RTS

*-------------------------------------------------
* Free master index/index block entries
* If DeAlockBlkZ is used, (Y) must be set correctly

DeAllocBlk  LDY    #$00            ;Start at the beginning
DeAlocBlkZ  LDA    blockNum        ;Save disk address
            PHA                    ; of genBuf's data
            LDA    blockNum+1
            PHA

:loop       STY    sapPtr          ;Save current index
            LDA    genBuf,Y        ;Get address (low) of block to be deallocated
            CMP    #$01            ;Test for NULL block
            LDX    genBuf+$100,Y   ;Get the rest of the block address
            BNE    :1              ;Branch if not NULL
            BCC    :2              ;Skip it if NULL

:1          JSR    Dealloc         ;Free it up on volume bitMap
            BCS    :3              ;Return any error
            LDY    sapPtr          ;Get index to sapling level index block again
            JSR    SwapMe

:2          INY                    ;Point at next block address
            BNE    :loop           ;Branch if more to deallocate (or test)

            CLC                    ;Indicate no error
:3          TAX                    ;Save error code, if any
            PLA
            STA    blockNum+1
            PLA
            STA    blockNum
            TXA                    ;Restore return code
            RTS

**************************************************
* delFlag = 0 - Not called by Destroy
* delFlag = 1 - Called Destroy ie swapping
* Swap the Lo & Hi indices making up a disk addr
* so that disk recovery programs may be able
* to undelete a destroyed file

SwapMe      LDA    delFlag         ;Are we swapping or zeroing ?
            BNE    :1              ;Skip if swapping
            TAX                    ;Make X a 0
            BEQ    :2              ;0 the index  (always taken)

:1          LDX    genBuf+$100,Y   ;Get index, hi
            LDA    genBuf,Y        ;Get index, lo
:2          STA    genBuf+$100,Y   ;Save index, hi
            TXA
            STA    genBuf,Y        ;Save index, lo
            RTS                    ;We're done