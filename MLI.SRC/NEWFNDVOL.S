**************************************************
* Get directory data

PrepRoot    JSR    FindVol         ;Search VCB's and devices for specified volume
            BCS    NoVolume        ;Branch if not found

            LDA    #$00            ;Zero out directory temps
            LDY    #$42
ClrDsp      STA    ownersBlock,Y   ; & owner info
            DEY
            BPL    ClrDsp

            LDA    DevNum          ;Set up device number for this directory
            STA    d_dev
            JSR    MoveHeadZ       ;Set up other header info from directory

            LDY    #$01            ; in genBuf & clean up misc
            LDX    vcbPtr
            INX
RootMisc    LDA    vcb+vcbTotBlks,X;Misc info includes
            STA    h_totBlk,Y      ; total # of blocks,
            LDA    vcb+vcbBitMap,X ; the disk addr of the first bitmap,
            STA    h_bitMap,Y
            LDA    |blockNum,Y     ; directory's disk address,
            STA    d_head,Y
            LDA    h_fileCnt,Y     ; & lastly, setting up a counter for
            STA    entCnt,Y        ; the # of files in this directory
            DEX                    ;Move low order bytes too
            DEY
            BPL    RootMisc

NxtPName    JSR    NxtPNameZ       ;Get new pnPtr in Y & next namlen in A
            STY    pnPtr           ;Save new pathname pointer
            RTS                    ;(status reg according to ACC)

*-------------------------------------------------
* Advance to next dir name

NxtPNameZ   LDY    pnPtr           ;Bump pathname pointer to
            LDA    pathBuf,Y       ; next name in the path...
            SEC
            ADC    pnPtr           ;If this addition results in zero
            TAY                    ; then prefixed directory has been moved
            BNE    :1              ; to another device. Branch if not

            LDA    DevNum          ;Revise devnum for prefixed directory
            STA    pathDev
:1          LDA    pathBuf,Y       ;Test for end of name (Z=1)
            CLC                    ;Indicate no errors
NoVolume    RTS

*-------------------------------------------------
* Find base dir

FindVol     LDA    #$00
            LDY    PfixPtr         ;Use prefix volume name to look up VCB
            BIT    prfxFlg         ;Is this a prefixed path?
            BPL    :1              ;Branch if it is
            TAY                    ;Set ptr to volume name

:1          STY    vnPtr           ;Save pointer
            STA    DevNum          ;Zero out device number until VCB located

Adv2NxtVCB  PHA                    ;Acc now used as VCB lookup index
            TAX                    ;Move pointer to X-reg for index
            LDA    vcb+vcbNamLen,X ;Get volume name length
            BNE    MatchVol        ;Branch if claimed VCB to be tested
NxtVCB      LDY    vnPtr           ;Restore ptr to requested volume name
            PLA                    ;Now adjust VCB index to next vcb entry
            CLC
            ADC    #vcbSize
            BCC    Adv2NxtVCB      ;Branch if more VCB's to check
            BCS    LookVol         ;Otherwise go look for unlogged volumes

MatchVol    STA    namCnt          ;Save length of vol name to be compared
:loop1      CMP    pathBuf,Y       ;Is it the same as requested vol name?
            BNE    NxtVCB          ;branch if not
            INX
            INY
            LDA    vcb+vcbName-1,X ;Bump to next character
            DEC    namCnt          ;Was that the last character?
            BPL    :loop1          ;Branch if not

            PLX                    ;Restore pointer to VCB that matches
            STX    vcbPtr          ;Save it for future reference
            LDA    vcb+vcbDevice,X ;Get its device number
            STA    DevNum          ;Save it
            STZ    blockNum+1      ;Assume prefix is not used and
            LDA    #$02            ; that root directory is to be used
            STA    blockNum

            LDA    vnPtr           ;= 0 if no prefix
PfxDir      TAY                    ;If prefix, then find ptr to prefixed dir name
            STA    pnPtr           ;Save path ptr
            BEQ    ChkVolName      ;Branch if no prefix
            SEC                    ;Bump to next dir in prefix path
            ADC    pathBuf,Y
            BCC    PfxDir          ;Branch if there is another dir in prefix

            LDA    pathBlok        ;Volume verification will occur
            STA    blockNum        ; at sub directory level
            LDA    pathBlok+1
            STA    blockNum+1

*-------------------------------------------------
******verify volume name****** 

ChkVolName  JSR    RdGBuf          ;Read in directory (or prefix directory)
            BCS    WrgVol          ;If error then look on other devices
            JSR    CmpPName        ;Compare directory name with pathname
            BCC    WrgVolErr       ;If they match, don't look elsewhere

WrgVol      LDX    vcbPtr          ;Find out if current (matched) vcb is active
            LDA    vcb+vcbStatus,X ; i.e. does it have open files?
            BMI    LookVolErr      ;Report not found if active

LookVol     LDA    vnPtr           ;Make path pointer same as volume ptr
            STA    pnPtr
            JSR    MovDevNums      ;Copy all device numbers to be examined
            LDA    DevNum          ;Log current device first, before searching others
            BNE    WrgVol3

TryNxtUnit  LDX    DevCnt          ;Scan look list for devices we need
:loop       LDA    lookList,X      ; to search for the requested volume
            BNE    WrgVol4         ;Branch if we've a device to look at
            DEX
            BPL    :loop           ;Look at next guy

LookVolErr  LDA    #volNotFound    ;Report that no mounted volume
            SEC                    ; matches the requested
WrgVolErr   RTS

WrgVol3     LDX    DevCnt          ;Now remove the device from the list
WrgVol4     CMP    lookList,X      ; of prospective devices (so we don't look twice)
            BEQ    :1              ;Branch if match
            DEX                    ;Look until found
            BPL    WrgVol4         ;Branch always taken! (usually!) * * *
            BMI    LookVolErr      ;Never unless device was manually removed from devlst (/ram)

:1          STA    DevNum          ;Preserve device we're about to investigate
            STZ    lookList,X      ;Mark this one as tested
            JSR    ScanVCB         ;Find VCB that claims this device, if any
            BCS    FndVolErr       ;Branch if VCB full
            LDX    vcbPtr          ;Did 'fnddvcb' find it or did it return free vcb?
            LDA    vcb,X
            BEQ    :2              ;Branch if free VCB
            LDA    vcb+vcbStatus,X ;Is this volume active?
            BMI    TryNxtUnit      ;If so, no need to re-log

:2          LDA    #$02            ;Go read root directory into genBuf
            LDX    #$00
            JSR    RdBlkAX
            BCS    TryNxtUnit      ;Ignore if unable to read
            JSR    LogVCB          ;Go log in this volume's proper name
            BCS    TryNxtUnit      ;Look at next if non xdos disk was mounted
            JSR    CmpPName        ;Is this the volume we're looking for?
            BCS    TryNxtUnit      ;Branch if not
FndVolErr   RTS                    ;return to caller

MovDevNums  LDX    DevCnt          ;Copy all device numbers to be examined
:loop       LDA    DevLst,X
            AND    #$F0            ;Strip device type info
            STA    lookList,X      ;Copy them to a temporary workspace
            DEX
            BPL    :loop
            LDX    DevCnt
            RTS

**************************************************
* Scan VCBs' for device #
* Input
*  (DevNum) - Look for vcb with this device number
* Output
*   C = - Got a match/Got a free slot

ScanVCB     LDA    #$00
            LDY    #$FF
ScanNxtVCB  TAX                    ;New index to next VCB
            LDA    vcb+vcbDevice,X ;Check all devnums
            CMP    DevNum          ;Is this the VCB were looking for?
            BNE    NotThisVCB      ;Branch if not
            STX    vcbPtr
            CLC                    ;Indicate found
            RTS

NotThisVCB  LDA    vcb,X           ;Is this a free VCB?
            BNE    :1              ;Branch if not
            INY
            STX    vcbPtr
:1          TXA                    ;now...
            CLC                    ; bump index to next VCB
            ADC    #vcbSize
            BNE    ScanNxtVCB
            TYA                    ;Were any free VCB's available?
            BPL    :3              ;Yes

            LDA    #$00
:loop       TAX                    ;Save index
            LDA    vcb+vcbStatus,X ;Any files opened?
            BPL    :2              ;No
            TXA
            CLC
            ADC    #vcbSize
            BNE    :loop
            BEQ    :ErrExit        ;Always

:2          STX    vcbPtr          ;This slot can be used
            STZ    vcb,X           ;Prepare it for use
            STZ    vcb+vcbDevice,X
:3          CLC                    ;Indicate no errors
:ErrExit    LDA    #vcbFullErr
            RTS

*-------------------------------------------------
* Compare dir name with path level

CmpPName    LDX    #$00            ;Index to directory name
            LDY    pnPtr           ;Index to pathname
            LDA    genBuf+4+hNamLen;Get directory name length (and type)
            CMP    #$E0            ;Also make sure it's a directory
            BCC    :1              ;Branch if not a directory
            AND    #$0F            ;Isolate name length
            STA    namCnt          ;Save as counter
            BNE    :2              ;Branch if valid length
:1          SEC                    ;Indicate not what were looking for
            RTS

:loop       LDA    genBuf+4+hName-1,X;Get next char
:2          CMP    pathBuf,Y
            BNE    :1              ;Branch if not the same
            INX                    ;Check nxt char
            INY
            DEC    namCnt
            BPL    :loop           ;Branch if more to compare
            CLC                    ;Otherwise we got a match!!!
            RTS

*-------------------------------------------------
* Mount new volume

LogVCB      LDX    vcbPtr          ;Is this a previously logged in volume
            LDA    vcb,X           ;(A=0?)
            BEQ    LogVCBZ         ;No, go ahead and prepare vcb
            JSR    CmpVCB          ;Does VCB match volume read?
            BCC    VCBLogged       ;Yes, don't disturb it

LogVCBZ     LDY    #vcbSize-1
ZeroVCB     STZ    vcb,X           ;Zero out VCB entry
            INX
            DEY
            BPL    ZeroVCB

            JSR    TestSOS         ;Make sure it's an xdos diskette
            BCS    VCBLogged       ;If not, return carry set

            JSR    TestDupVol      ;find out if a duplicate with open files already exists
            BCS    NotLog0
            LDA    genBuf+4+hNamLen;Move volume name to VCB
            AND    #$0F            ;Strip root marker
            TAY                    ;len byte to Y-reg
            PHA
            ORA    vcbPtr          ;Add in offset to VCB record
            TAX
MovVolNam   LDA    genBuf+4+hNamLen,Y
            STA    vcb+hNamLen,X
            DEX
            DEY
            BNE    MovVolNam

            PLA                    ;Get length again
            STA    vcb+hNamLen,X   ;Save that too.
            LDA    DevNum
            STA    vcb+vcbDevice,X ;Save device number also
            LDA    genBuf+4+vTotBlk; & totol # of blocks on this unit,
            STA    vcb+vcbTotBlks,X
            LDA    genBuf+4+vTotBlk+1
            STA    vcb+vcbTotBlks+1,X
            LDA    blockNum        ; & address of root directory
            STA    vcb+vcbRoot,X
            LDA    blockNum+1
            STA    vcb+vcbRoot+1,X

            LDA    genBuf+4+vBitMap; & lastly, the address
            STA    vcb+vcbBitMap,X ; of the first bitmap
            LDA    genBuf+4+vBitMap+1
            STA    vcb+vcbBitMap+1,X
NotLog0     CLC                    ;Indicate that it was logged if possible
VCBLogged   RTS

*-------------------------------------------------
* Compare vol names to make sure they match

CmpVCB      LDA    genBuf+4+hNamLen;Compare volume name in VCB
            AND    #$0F            ; with name in directory
            CMP    vcb+hNamLen,X   ;Are they same length?
            STX    xvcbPtr
            BNE    :1

            TAY
            ORA    xvcbPtr
            TAX
:CmpLoop    LDA    genBuf+4+hNamLen,Y
            CMP    vcb+hNamLen,X
:1          SEC                    ;Anticipate different names
            BNE    NotSame
            DEX
            DEY
            BNE    :CmpLoop

            CLC                    ;Indicate match
NotSame     LDX    xvcbPtr         ;Get back offset to start of vcb
            RTS

*-------------------------------------------------
* Look for duplicate vol

TestDupVol  LDA    #$00            ;Look for other logged in volumes with same name
:loop       TAX
            JSR    CmpVCB
            BCS    :1              ;Branch if no match

            LDA    vcb+vcbStatus,X ;Test for any open files
            BMI    FoundDupVol     ;Tell the sucker he can't look at this volume!

            LDA    #$00            ;Take duplicate off line if no open file
            STA    vcb,X
            STA    vcb+vcbDevice,X
            BEQ    NoDupVol        ;Return that all is ok to log in new

:1          TXA                    ;Index to next VCB
            CLC
            AND    #$E0            ;Strip odd stuff
            ADC    #vcbSize        ;Bump to next entry
            BCC    :loop           ;Branch if more to look at

NoDupVol    CLC
            RTS

FoundDupVol STA    duplFlag        ;A duplicate has been detected
            STX    vcbEntry        ;Save pointer to conflicting vcb
            SEC                    ;Indicate error
            RTS
*-------------------------------------------------
* See if a quantity of free blks is available on volume
* Input
*  (reqL,H) = # of blks required

TestFreeBlk LDX    vcbPtr          ;Find out if enough free blocks
            LDA    vcb+vcbFreeBlks+1,X; available to accomodate the request
            ORA    vcb+vcbFreeBlks,X; but first find out if we got a proper cnt for this vol
            BNE    CmpFreeBlk      ;Branch if count is non-zero

* Compute VCB free blk count

TakeFreeCnt JSR    CntBMs          ;Get # of bitmaps
            STA    bmCnt           ;Save it
            STZ    scrtch          ;Start count at zero
            STZ    scrtch+1
            LDA    #$FF            ;Mark 'first free' temp as unknown
            STA    noFree
            JSR    UpdateBitMap    ;(nothing happens if it don't hafta.)
            BCS    TFBErr          ;Branch if we got trouble

            LDX    vcbPtr          ;Get address of first bit map
            LDA    vcb+vcbBitMap,X
            STA    blockNum
            LDA    vcb+vcbBitMap+1,X
            STA    blockNum+1

BitMapRd    JSR    RdGBuf          ;Use g(eneral)buff(er) for temporary
            BCS    TFBErr          ; space to count free blocks (bits)
            JSR    FreeCount       ;Go count 'em
            DEC    bmCnt           ;Was that the last bit map?
            BMI    ChgVCB          ;If so, go change VCB to avoid doing this again!
            INC    blockNum        ;Note: the organization of the bit maps
            BNE    BitMapRd        ; are contiguous for sos version 0
            INC    blockNum+1      ;If some other organization is implemented,
            BRA    BitMapRd        ; this code must be changed! 

ChgVCB      LDX    vcbPtr          ;Mark which block had first free space
            LDA    noFree
            BMI    DskFull         ;Branch if no free space was found
            STA    vcb+vcbCurrBitMap,X;Update the free count
            LDA    scrtch+1        ;Get high count byte
            STA    vcb+vcbFreeBlks+1,X;Update volume control block
            LDA    scrtch
            STA    vcb+vcbFreeBlks,X; & low byte too...

CmpFreeBlk  LDA    vcb+vcbFreeBlks,X;Compare total available
            SEC
            SBC    reqL            ; free blocks on this volume
            LDA    vcb+vcbFreeBlks+1,X
            SBC    reqH
            BCC    DskFull
            CLC
            RTS

DskFull     LDA    #volumeFull
            SEC
TFBErr      RTS

*-------------------------------------------------
* Scan and count bitMap blks

FreeCount   LDY    #$00            ;Begin at the beginning
:loop       LDA    genBuf,Y        ;Get bit pattern
            BEQ    :1              ;Don't bother counting nothin'
            JSR    CntFree
:1          LDA    genBuf+$100,Y   ;Do both pages with same loop
            BEQ    :2
            JSR    CntFree
:2          INY
            BNE    :loop           ;Loop till all 512 bytes counted
            BIT    noFree          ;Has first block with free space been found yet?
            BPL    :3              ;Branch if it has

            LDA    scrtch          ;Test to see if any blocks were counted
            ORA    scrtch+1
            BEQ    :3              ;Branch if none counted

            JSR    CntBMs          ;Get total # of maps
            SEC                    ;Subtract countdown from total bit maps
            SBC    bmCnt
            STA    noFree
:3          RTS

*-------------------------------------------------
* Count # of 1 bits in a byte

CntFree     ASL
            BCC    :1              ;Not a 1-bit
            INC    scrtch
            BNE    :1
            INC    scrtch+1
:1          ORA    #$00            ;Loop until all bits counted
            BNE    CntFree
            RTS

*-------------------------------------------------
* Compute # of bit map blks-1

CntBMs      LDX    vcbPtr
            LDY    vcb+vcbTotBlks+1,X;Return the # of bit maps 
            LDA    vcb+vcbTotBlks,X; posible with the total count 
            BNE    :1              ; found in the vcb... 
            DEY                    ;Adjust for bitmap block boundary

:1          TYA
            LSR                    ;Divide by 16. The result is
            LSR                    ; the number of bit maps
            LSR
            LSR
            RTS