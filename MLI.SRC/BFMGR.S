            TTL    'ProDOS Block File Manager'
**************************************************
* ProDOS block file manager
* Perform filing or housekeeping functions
* (X)=call # ($00-$13)

BFMgr       LDA    Dispatch,X      ;Translate into command address
            ASL                    ;(bit 7 indicates a pathname to preprocess)
            STA    cmdTmp
            AND    #$3F            ;(bit6 is refnum preprocess, 5 is for time, so strip em.) 
            TAX
            LDA    cmdTable,X      ;Move address for indirect jump
            STA    goAdr
            LDA    cmdTable+1,X    ;(high byte)
            STA    goAdr+1
            LDA    #backupNeeded   ;Init "backup bit flag"
            STA    bkBitFlg        ; to say "file modified"
            BCC    NoPath

* For MLI calls $C0-$C4, $C8

            JSR    SetPath         ;Go process pathname before calling command
            BCS    ErrorSys        ;Branch if bad name

NoPath      ASL    cmdTmp          ;Test for refnum preprocessing
            BCC    NoPreRef

* For MLI calls $C9-$CB, $CE-$D3

            JSR    FindFCB         ;Go set up pointers to fcb and vcb of this file
            BCS    ErrorSys        ;branch if any errors are encountered

NoPreRef    ASL    cmdTmp          ;Lastly check for necessity of time stamp
            BCC    Execute

* For MLI calls $C0-$C4, $CC, $CD

            JSR    DateTime        ;(No error posible)

Execute     JSR    GoCmd           ;Execute command
            BCC    GoodOp          ;Branch if successful

ErrorSys    JSR    SysErr          ;Don't come back
GoodOp      RTS                    ;Good return 

*-------------------------------------------------
* Check caller's pathname & copy to pathname buffer

SetPath     LDY    #c_path
            LDA    (parm),Y        ;Get low pointer addr
            STA    tPath
            INY
            LDA    (parm),Y
            STA    tPath+1         ; & hi pointer addr

SynPath     EQU    *               ;Entry used by rename for second pathname
            LDX    #$00            ;X-reg is used as index to pathBuf
            LDY    #$00            ;Y-reg is index to input pathname
            STX    prfxFlg         ;Assume prefix is in use
            STX    pathBuf         ;Mark pathbuf to indicate nothing processed
            LDA    (tPath),Y       ;Validate pathname length>0, and <65
            BEQ    ErrSyn
            CMP    #65
            BCS    ErrSyn
            STA    pathCnt         ;This is used to compare for
            INC    pathCnt         ; end of pathname processing
            INY                    ;Now check for full pathname...
            LDA    (tPath),Y       ;(Full name if starts with "/")
            ORA    #$80
            CMP    #"/"
            BNE    NotFullPN       ;Branch if prefix appended
            STA    prfxFlg         ;Set prefix flag to indicate prefix not used
            INY                    ;Index to first character of pathname

NotFullPN   LDA    #$FF            ;Set current position of pathBuf
            STA    pathBuf,X       ; to indicate end of pathname
            STA    namCnt          ;Also indicate no characters processed in local name
            STX    namPtr          ;Preserve pointer to local name length byte

SynPath3    CPY    pathCnt         ;done with pathname processing?
            BCS    EndPath         ;Yes
            LDA    (tPath),Y       ;Get character
            AND    #$7F            ;We're not interested in high order bit
            INX                    ;Prepare for next character
            INY
            CMP    #'/'            ;Is it a slash delimiter?
            BEQ    EndName         ;Branch if it is
            CMP    #'a'            ;Is it lower case character?
            BCC    NotLower        ;Branch if not
            AND    #$5F            ;Upshift to upper case
NotLower    STA    pathBuf,X       ;Store charcter
            INC    namCnt          ;Is it the first of a local name?
            BNE    NotFirst        ;Branch if not
            INC    namCnt          ;Kick count to 1
            BNE    TestAlfa        ;First char. Must be alpha (branch always taken)

NotFirst    CMP    #'.'            ;Is it "."?
            BEQ    SynPath3        ;It's ok if it is, do next char
            CMP    #'0'            ;Is it at least "0"?
            BCC    ErrSyn          ;Report syntax error if not
            CMP    #'9'+1          ;Is it numeric?
            BCC    SynPath3        ;ok if it is, do next character

TestAlfa    CMP    #'A'            ;Is it at least an "a"?
            BCC    ErrSyn          ;Report err if not
            CMP    #'Z'+1          ;Is it g.t. "z"?
            BCC    SynPath3        ;Get next char if valid alpha
ErrSyn      SEC                    ;Make sure carry set
            LDA    #badPathSyntax
            RTS                    ;Report error

EndPath     LDA    #$00            ;End pathname with 0
            BIT    namCnt          ;Also make sure name count is positive
            BPL    :1
            STA    namCnt          ;=0
            DEX
:1          INX
            STA    pathBuf,X
            BEQ    ErrSyn          ;Report error if "/" only
            STX    pathCnt         ;Save true length of pathname
            TAX                    ;X=0 causes end of process, after endname

EndName     LDA    namCnt          ;Validate local name <16
            CMP    #15+1
            BCS    ErrSyn
            PHX                    ;Save current pointer
            LDX    namPtr          ;Get index to beginning of local name
            STA    pathBuf,X       ;Save local name's length
            PLX                    ;Restore x
            BNE    NotFullPN       ;Branch if more names to process

            CLC                    ;Indicate success!
            LDA    prfxFlg         ; but make sure all pathnames are
            BNE    EndRTS          ; prefixed or begin with a "/"
            LDA    NewPfxPtr       ; must be non-zero
            BEQ    ErrSyn
EndRTS      RTS

**************************************************
* SETPREFIX Call

SetPrefix   JSR    SetPath         ;Call is made here so a 'null' path may be detected
            BCC    :1              ;Branch if pathname ok
            LDY    pathBuf         ;Was it a nul pathname?
            BNE    PfxErr          ;Branch if true syntax error
            JSR    ZeroPfxPtrs     ;Indicate null prefix. NB. (Y)=0
            CLC
            RTS

:1          JSR    FindFile        ;Go find specified prefix directory
            BCC    :2              ;Branch if no error
            CMP    #badPathSyntax
            BNE    PfxErr          ;Branch if error is real (not root dir) 

:2          LDA    d_file+d_stor   ;Make sure last local name is DIR type
            AND    #directoryFile*16;(either root or sub)
            EOR    #directoryFile*16;Is it a directory?
            BNE    PfxTypErr       ;Report wrong type
            LDY    prfxFlg         ;New or appended prefix?
            BNE    :3              ;(A)=0 if branch taken
            LDA    NewPfxPtr       ;Append new prefix to old
:3          TAY
            SEC                    ;Find new beginning of prefix
            SBC    pathCnt
            CMP    #$C0            ;Too long? ($100-$40)
            BCC    ErrSyn          ;Report it if so
            TAX
            JSR    SetPfxPtrs
            LDA    d_dev           ;Save device number
            STA    pathDev
            LDA    d_file+d_first  ; & addr of first block
            STA    pathBlok
            LDA    d_file+d_first+1
            STA    pathBlok+1
MovPrefix   LDA    pathBuf,Y
            STA    pathBuf,X
            INY
            INX
            BNE    MovPrefix
            CLC                    ;Indicate good prefix
            RTS

PfxTypErr   LDA    #badStoreType   ;Report not a directory
PfxErr      SEC                    ;indicate error
            RTS

**************************************************
* GETPREFIX Call

GetPrefix   CLC                    ;Calculate how big a buffer is needed to 
            LDY    #c_path         ;Get index to user's pathname buffer
            LDA    (parm),Y
            STA    userBuf
            INY
            LDA    (parm),Y
            STA    userBuf+1
            STZ    cBytes+1        ;Set buf length at max
            LDA    #64             ;(64 characters max)
            STA    cBytes
            JSR    ValDBuf         ;Go validate prefix buffer addr
            BCS    PfxErr
            LDY    #$00            ;Y is indirect index to user buffer
            LDA    NewPfxPtr       ;Get address of beginning of prefix
            TAX
            BEQ    NullPrefix      ;Branch if null prefix
            EOR    #$FF            ;Get total length of prefix
            ADC    #$02            ;Add 2 for leading and trailing slashes
NullPrefix  STA    (userBuf),Y     ;Store length in user's buffer
            BEQ    GotPrefix       ;Branch if null prefix
SendPrefix  INY                    ;Bump to next user buf loc
            LDA    pathBuf,X       ;Get next char of prefix
SndLimit    STA    (userBuf),Y     ;Give character to user
            AND    #$F0            ;Check for length descriptor
            BNE    :1              ;Branch if regular character
            LDA    #'/'            ;Otherwise, substitute a slash
            BNE    SndLimit        ;Branch always

:1          INX
            BNE    SendPrefix      ;Branch if more to send
            INY
            LDA    #'/'            ;End with slash
            STA    (userBuf),Y
GotPrefix   CLC                    ;Indicate no error
            RTS

*-------------------------------------------------
* Validity check the ref # passed by caller

FindFCB     LDY    #c_refNum       ;Index to reference number
            LDA    (parm),Y        ;Is it a valid file number?
            BEQ    ErrRefNum       ;Must not be 0!
            CMP    #8+1            ;Must be 1 to 8 only
            BCS    ErrRefNum       ;User must be stoned...
            PHA
            DEC                    ;(subtracts 1)
            LSR                    ;Shift low 3 bits to high bits
            ROR
            ROR
            ROR                    ;Effective multiply by 32
            STA    fcbPtr          ;Later used as an index
            TAY                    ; to FCB like now
            PLA                    ;Restore refnum in A-reg
            CMP    fcb+fcbRefNum,Y ;Is it an open reference?
            BNE    ErrNoRef        ;Branch if not

FndFCBuf    LDA    fcb+fcbFileBuf,Y;Get page addr of file buffer
            JSR    GetBufAdr       ;Get file's address into bufAddrL & H
            LDX    bufAddrH        ;(Y)=fcbptr - preserved
            BEQ    FCBDead         ;Report FCB screwed up!!!
            STX    dataPtr+1       ;Save pointer to data area of buffer
            INX
            INX                    ;Index block always 2 pages after data
            STX    tIndex+1
            LDA    fcb+fcbDevNum,Y ;Also set up device number
            STA    DevNum
            LDA    bufAddrL
            STA    dataPtr         ;Index and data buffers
            STA    tIndex          ; always on page boundaries

SrchVCBs    TAX                    ;Search for associated VCB
            LDA    vcb+vcbDevice,X
            CMP    fcb+fcbDevNum,Y ;Is this VCB the same device?
            BEQ    TestVOpen       ;If it is, make sure volume is active

NxtBufr     TXA                    ;Adjust index to next VCB
            CLC
            ADC    #vcbSize
            BCC    SrchVCBs        ;Loop until volume found
            LDA    #vcbUnusable    ;Report open file has no volume...
            JSR    SysDeath        ; & kill the system

FCBDead     LDA    #fcbUnusable    ;Report FCB trashed
            JSR    SysDeath        ; & kill the system

TestVOpen   LDA    vcb,X           ;Make sure this VCB is open
            BEQ    NxtBufr         ;Branch if it is not active
            STX    vcbPtr          ;Save pointer to good VCB
            CLC                    ;Indicate all's well
            RTS

ErrNoRef    LDA    #$00            ;Drop a zero into this FCB
            STA    fcb+fcbRefNum,Y ; to show free FCB

ErrRefNum   LDA    #invalidRefNum  ;Tell user that requested refnum
            SEC                    ; is illegal (out of range) for this call
            RTS

**************************************************
* ONLINE call

Online      JSR    MovDBuf         ;Move user specified buffer pointer to usrbuf
            STZ    cBytes          ;Figure out how big buffer has to be
            STZ    cBytes+1
            LDY    #c_devNum
            LDA    (parm),Y        ;If zero then cbytes=$100, else =$010 for one device
            AND    #$F0
            STA    DevNum
            BEQ    :1              ;Branch if all devices
            LDA    #$10
            STA    cBytes
            BNE    :2              ;Always
:1          INC    cBytes+1        ;Allow for up to 16 devices
:2          JSR    ValDBuf         ;Go validate buffer range against allocated memory
            BCS    OnlinErr
            LDA    #$00            ;Zero out user buffer space
            LDY    cBytes
:loop1      DEY
            STA    (userBuf),Y     ;Zero either 16 or 256 bytes
            BNE    :loop1          ;Branch if more to zero
            STA    namPtr          ;Use namPtr as pointer to user buffer
            LDA    DevNum
            BNE    OnlineZ         ;Branch if only 1 device to process
            JSR    MovDevNums      ;Get list of currently recognized devices
:loop2      PHX                    ;Save index to last item on list
            LDA    lookList,X      ;Get next device #
            STA    DevNum
            JSR    OnlineZ         ;Log this volume and return it's name to user
            LDA    namPtr
            CLC
            ADC    #$10
            STA    namPtr
            PLX                    ;Restore index to device list
            DEX                    ;Index to next device
            BPL    :loop2          ;Branch if there is another device
            LDA    #$00            ;No errors for muliple on-line
            CLC                    ;Indicate good on all volumes
OnlinErr    RTS

* Generate return data for a specific device

OnlineZ     JSR    ScanVCB         ;See if it has already been logged in
            BCS    OnlinErr1       ;Branch if VCB is full
            LDX    #$00            ;Read in root (volume) directory
            LDA    #$02            ;(X,A)=block #
            JSR    RdBlkAX         ;Read it into general purpose buffer
            LDX    vcbPtr          ;Use x as an index to the vcb entry

* This fix is to remove VCB entries that correspond to devices that
* are no longer in the device list (i.e. removed by the user).

            BCC    VolFound        ;Branch if the read was ok
            TAY                    ;Save error value in Y-reg
            LDA    vcb+vcbStatus,X ;Don't take the VCB off line if
            BNE    RtrnErr         ; there are active files present!
            STA    vcb,X           ;Now take the volume off line
            STA    vcb+vcbDevice,X
RtrnErr     TYA                    ;Now return error to A
            BCS    OnlinErr1

* 1st vol dir blk has been read successfully

VolFound    LDA    vcb,X           ;Has it been logged in before?
            BEQ    :1              ;Branch if not
            LDA    vcb+vcbStatus,X ;It has, are there active files?
            BMI    :2              ;Branch if the volume is currently busy
:1          JSR    LogVCBZ         ;Go log it in
            BCS    OnlinErr1       ;Branch if there is some problem (like notsos)
            LDA    #dupVolume      ;Anticipate a duplicate active volume exists
            BIT    duplFlag
            BMI    OnlinErr1       ;Branch if we guessed right
:2          LDX    vcbPtr          ;Restore vcbptr just in case we lost it
            JSR    CmpVCB          ;Does read in volume compare with logged volume?
            LDA    #drvrDiskSwitch ;Anticipate wrong volume mounted in active device
            BCC    Online2         ;Branch if no problem!

* On fall thru, (A)=disk switch error
* Store error code in user's data buffer

OnlinErr1   PHA                    ;Save error code
            JSR    SavDevNbr       ;Tell user what device we looked at
            PLA                    ;Get error code again
            INY                    ;Tell user what error was encountered on this device
            STA    (userBuf),Y
            CMP    #dupVolume      ;Was it a duplicate volume error?
            BNE    :1              ;Branch if not,
            INY                    ;Otherwise tell user which other device has same name
            LDX    vcbEntry
            LDA    vcb+vcbDevice,X
            STA    (userBuf),Y
            STZ    duplFlag        ;Clear duplicate flag
            LDA    #dupVolume      ;Restore error code
:1          SEC                    ;Indicate error
            RTS

* Make online volume entry

Online2     LDA    vcb,X           ;Get volume name count
            STA    namCnt
            LDY    namPtr          ;Index to user's buffer
:loop       LDA    vcb,X           ;Move name to user's buffer
            STA    (userBuf),Y
            INX
            INY
            DEC    namCnt          ;Loop until all characters moved
            BPL    :loop

SavDevNbr   LDY    namPtr          ;Index to first byte of this entry
            LDA    DevNum          ;Put device number in upper nibble of this byte
            ORA    (userBuf),Y     ;Lower nibble is name length
            STA    (userBuf),Y
            CLC                    ;Indicate no errors
            RTS
