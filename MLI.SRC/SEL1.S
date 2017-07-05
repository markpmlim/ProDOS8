**************************************************
* Zero page use

SMrkPBlk    EQU    $60             ;SetMark parm blk
numActvDev  EQU    $65             ;# of active devices-1
currEnt     EQU    $67
listTotal   EQU    $68             ;tot # of SYS/DIR entries in curr dir
fnameLen    EQU    $69
dispCnt     EQU    $6A             ;# of entries displayed
depth       EQU    $6B             ;0=unit, 1=root dir
fnamePtr    EQU    $6C
Entry_Len   EQU    $6E             ;These are read fr dir file
EntPerBlk   EQU    $6F
FileCount   EQU    $70
entryNum    EQU    $72             ;entry # within dir block
scrolledNum EQU    $73             ;# of entries that were scrolled up

fTypeTbl    EQU    $74             ;$74-$F3 (128 entries)
namesBuf    EQU    $1400           ;Store for file incl subdir names
P8IOBuf     EQU    $1C00           ;1024-byte buf for opened files
entryBuf    EQU    $2000           ;Read buf for file entry & vol/sub dir header recs

**************************************************
* Improved Dispatcher/Selector

            ORG    DispAdr
            MX     %11

BetterBye   CLD                    ;Flag this is a SELECTOR
            LDA    RDROM2          ;Enable Motherboard ROM
            STZ    SOFTEV
            LDA    #>BetterBye
            STA    SOFTEV+1
            JSR    SETPWRC         ;Set powerup byte
            LDA    #$A0            ;Switch on $C3 video
            JSR    $C300

            LDX    #23
:ClrLoop    STZ    memTabl,X
            DEX
            BPL    :ClrLoop

            INC    memTabl+23      ;Protect $BF page
            LDA    #%11001111      ;Flag $00,$01 & $04-$07 mem
            STA    memTabl         ; pages as being used
            LDA    #$02
            STA    SMrkPBlk        ;Set pCount
            LDX    DevCnt          ;Get # of devices-1
            STX    numActvDev
            LDA    DevNum          ;Is there a last accessed dev?
            BNE    IsDevOL         ;Yes, start with that one

*-------------------------------------------------

NxtActvDev  LDX    numActvDev      ;Start search fr this
            LDA    DevLst,X        ;=DSSS IIII
            CPX    #$01            ;Last on the list?
            BCS    :1              ;No
            LDX    DevCnt          ;Start all over again
            INX
:1          DEX
            STX    numActvDev

IsDevOL     STA    OLUnit          ;Chk if vol is online
            JSR    GoPro
            DB     $C5
            DA     OLinPBlk
            BCS    NxtActvDev      ;No, try next device

            STZ    depth
            LDA    pnBuf+1         ;=DSSS LLLL
            AND    #$0F            ;Isolate name len of vol
            BEQ    NxtActvDev      ;Not online
            ADC    #$02            ;For the 2 added slashes
            TAX

OpenFolder  STX    pnBuf           ;len of PN
            LDA    #'/'            ;Add a slash to the
            STA    pnBuf+1
            STA    pnBuf,X         ; beginning & end of PN
            STZ    pnBuf+1,X
            JSR    GoPro           ;Open the vol/sub dir
            DB     $C8
            DA     OpenPBlk
            BCC    FolderOpened

            LDA    depth
            BEQ    NxtActvDev
            JSR    BELL1
            JSR    ChopName
            STX    pnBuf
            JMP    GetKeyPress     ;Pause

*-------------------------------------------------

FolderOpened       INC             depth
            STZ    listTotal       ;# of SYS/DIR entries
            LDA    OpenRef
            STA    ReadRef
            STA    SMrkPBlk+c_refNum;Set ref #
            LDA    #$27+4          ;Read in the link blk ptrs
            STA    RdReqLen        ; & vol/subdir header rec
            STZ    RdReqLen+1
            JSR    ReadEntry
            BCS    ScanDirDone

            LDX    #$03            ;Copy the file count,
:CpyLoop    LDA    entryBuf+hEntLen+4,X; entries/blk
            STA    Entry_Len,X     ; & entry len
            DEX
            BPL    :CpyLoop

            STA    RdReqLen        ;=entry_len ($27)
            LDA    #$01            ;Start w/first file entry
            STA    entryNum        ; skipping the header entry
            STZ    SMrkPBlk+c_mark+1
            STZ    SMrkPBlk+c_mark+2
            LDA    FileCount       ;Is vol/sub dir empty?
            ORA    FileCount+1
            BNE    NxtFilEnt       ;No
ScanDirDone BRA    ClsDirFile      ;Done with reading dir

NxtFilEnt   BIT    FileCount+1     ;Any more file entries?
            BMI    ScanDirDone     ;Done

SkipEnt     LDA    SMrkPBlk+c_mark+1
            AND    #%11111110      ;Do a MOD 512 to force
            STA    SMrkPBlk+c_mark+1; a block alignment
            LDY    entryNum
            LDA    #$00
            CPY    EntPerBlk
            BCC    CalcOffset

            TAY                    ;Y=0
            STY    entryNum
            INC    SMrkPBlk+c_mark+1;On fall thru next block
NxtPage     INC    SMrkPBlk+c_mark+1;2nd page of block

CalcOffset  DEY                    ;Compute offset to file entry
            CLC
            BMI    SetFilePos
            ADC    Entry_Len
            BCC    CalcOffset
            BCS    NxtPage         ;Always

SetFilePos  ADC    #$04            ;Skip 4-byte header
            STA    SMrkPBlk+c_mark
            JSR    GoPro
            DB     $CE
            DA     SMrkPBlk
            BCS    ScanDirDone

            JSR    ReadEntry
            BCS    ScanDirDone
            INC    entryNum
            LDA    entryBuf+d_stor ;Get storType/namelen
            AND    #$F0            ;Isolate storage type
            BEQ    SkipEnt         ;Deleted entry
            DEC    FileCount
            BNE    GoodRead
            DEC    FileCount+1

GoodRead    ROR    entryBuf+d_attr ;Check readEnable bit
            BCC    NxtFilEnt       ;File cannot be read
            LDA    entryBuf+d_fileID;Get file type
            CMP    #$0F            ;Is it a DIR file?
            BEQ    :1              ;Yes
            CMP    #$FF            ;SYS file?
            BNE    NxtFilEnt       ;No
            
:1          LDX    listTotal       ;# of SYS/DIR entries
            CPX    #128
            BCS    ClsDirFile
            STA    fTypeTbl,X      ;Store filetype
            JSR    GetNameSlot

            LDY    #15
:CpyLoop    LDA    entryBuf+d_stor,Y;Copy filename including
            STA    (fnamePtr),Y    ; the storType/namelen byte
            DEY
            BPL    :CpyLoop

            INY                    ;Y=0 ;(A)=storType/namelen
            AND    #$0F            ;Isolate len byte
            STA    (fnamePtr),Y    ;Save it
            INC    listTotal       ;# of SYS/DIR entries
            BNE    NxtFilEnt

CantCls     JMP    NxtActvDev      ;Hitch a ride

ClsDirFile  JSR    GoPro
            DB     $CC
            DA     ClsPBlk
            BCS    CantCls

* Display list of files in vol/subdir

            JSR    SETTXT
            JSR    HOME            ;Clear scrn & posn cursor @ top of scrn
            LDA    #23
            JSR    TABV            ;Posn cursor @ btm of scrn
            LDY    #helpStr-helpStr
            LDA    #20             ;Display Help Message
            JSR    ShowHelp        ; starting @ scrn coords (23, 20)

            JSR    HomeCursor
            LDX    #$00
:loop       LDA    pnBuf+1,X       ;Display full PN
            BEQ    :1              ; at top of screen
            JSR    PrtChar
            INX
            BNE    :loop

:1          STZ    currEnt
            STZ    scrolledNum
            LDA    listTotal       ;# of SYS/DIR entries
            BEQ    GetKeyPress

            CMP    #21
            BCC    :2
            LDA    #20             ;Only 20 will be displayed
:2          STA    dispCnt
            LDA    #2              ;Set the dimensions
            STA    WNDTOP          ; of our display window
            STA    WNDLFT          ; which is (2, 2) to (22, 24)
            LDA    #22
            STA    WNDWDTH
            STA    WNDBTM

:DspLoop    JSR    ShowEntry
            INC    currEnt
            DEC    dispCnt
            BNE    :DspLoop

            STZ    currEnt         ;Highlight 1st entry
            BEQ    InvDsp          ;Always

UpArwHit    JSR    ShowEntry
            LDX    currEnt         ;Are we at the top of the list?
            BEQ    InvDsp          ;Yes -> No entries to scroll down
            DEC    currEnt
            LDA    CV              ;Are we at the top of our window?
            CMP    #$02
            BNE    InvDsp          ;No, proceed to highlight entry
            DEC    scrolledNum     ;Less 1 "scrolled up" entry
            LDA    #$16            ;Scroll down 1 line
            BNE    Scroll          ;always

DwnArwHit   JSR    ShowEntry
            LDX    currEnt         ;Is this the last SYS/DIR
            INX
            CPX    listTotal       ; entry in the dir?
            BCS    InvDsp          ;Yes -> No entries to scroll up
            STX    currEnt
            LDA    CV              ;Are we beyond the end of our window?
            CMP    #21
            BNE    InvDsp          ;No
            INC    scrolledNum     ;We have scrolled up 1 entry
            LDA    #$17            ;Scroll up 1 line
Scroll      JSR    COUT
InvDsp      JSR    SetInv          ;Set 80-col card to inverse mode
            JSR    ShowEntry

GetKeyPress LDA    KBD
            BPL    GetKeyPress

            STA    KBDSTROBE       ;Clear keyboard strobe
            JSR    SetNorm
            LDX    listTotal       ;Is vol/subdir empty?
            BEQ    :1              ;Yes, no entries were displayed

            CMP    #$8D            ;CR?
            BEQ    AcceptEnt
            CMP    #$8A            ;Down arrow?
            BEQ    DwnArwHit
            CMP    #$8B            ;Up arrow?
            BEQ    UpArwHit
:1          CMP    #$89            ;TAB?
            BEQ    NxtVol
            CMP    #$9B            ;ESC?
            BNE    GetKeyPress

            JSR    ChopName
            DEC    depth
            BRA    ToOpenDir2      ;Go open parent dir

* Scans the full pathname, and chops
* off characters until it gets to a /

ChopName    LDX    pnBuf           ;Get len of PN
:loop       DEX                    ;Bump to previous char
            LDA    pnBuf,X
            CMP    #'/'
            BNE    :loop
            CPX    #$01            ;Have we reached the root?
            BNE    :Rtn            ;No
            LDX    pnBuf           ;Stay at root level
:Rtn        RTS

NxtVol      JMP    NxtActvDev      ;Hitch a ride

ToOpenDir1  INX                    ;1 more for the ending slash
ToOpenDir2  JMP    OpenFolder

AcceptEnt   JSR    GoPro
            DB     $C6
            DA     SPfxPBlk
            BCS    NxtVol

* Extend the pathname

            LDX    currEnt
            JSR    GetNameSlot
            LDX    pnBuf           ;Append filename
:CpyLoop    INY
            LDA    (fnamePtr),Y    ; to the PN
            INX
            STA    pnBuf,X
            CPY    fnameLen
            BCC    :CpyLoop

            STX    pnBuf
            LDY    currEnt
            LDA    |fTypeTbl,Y     ;Get filetype
            BPL    ToOpenDir1      ;Dir file

            JSR    SETTXT
            JSR    HOME
            LDA    #$95            ;Deactivate 80-col, home cursor & clrsrcn
            JSR    COUT
            JSR    GoPro
            DB     $C8
            DA     OpenPBlk
            BCS    NxtVol

            LDA    OpenRef
            STA    ReadRef
            LDA    #$FF            ;Prepare to read the
            STA    RdReqLen        ; entire file whose
            STA    RdReqLen+1      ; len is unknown
            JSR    ReadEntry
            PHP                    ;Save err status
            JSR    GoPro
            DB     $CC
            DA     ClsPBlk
            PLP
            BCS    NxtVol          ;Read errs
            JMP    $2000           ;Transfer control to Applic

*-------------------------------------------------

ShowHelp    STA    CH
ShowIcon    EQU    *
:loop       LDA    helpStr,Y
            BEQ    :Rtn
            JSR    COUT
            INY
            BNE    :loop
:Rtn        RTS

*-------------------------------------------------
* Each file name 16 bytes/entry
* Allow up to 128 SYS/DIR names to be
* stored @ $1400-$1BFF
* Entry
*  (X) = entry #
* Exit
*  (Y) = 0
*  (fnamePtr) = Ptr to name of entry

GetNameSlot STZ    fnamePtr+1
            TXA
            ASL                    ;x16
            ROL    fnamePtr+1
            ASL
            ROL    fnamePtr+1
            ASL
            ROL    fnamePtr+1
            ASL
            ROL    fnamePtr+1
            STA    fnamePtr

            LDA    #>namesBuf
            CLC
            ADC    fnamePtr+1
            STA    fnamePtr+1
            LDY    #$00
            LDA    (fnamePtr),Y
            STA    fnameLen
            RTS

*-------------------------------------------------
* Display name of an entry

ShowEntry   LDA    #2
            STA    OURCH
            LDX    currEnt
            TXA
            SEC
            SBC    scrolledNum
            INC
            INC
            JSR    TABV
            LDA    fTypeTbl,X
            BMI    Its_Sys         ;SYS file
            STZ    OURCH           ;DIR file
            LDA    INVFLG
            PHA
            LDY    #FolderIcon-helpStr
            JSR    ShowIcon
            PLA
            STA    INVFLG

Its_Sys     JSR    PrtBlnk         ;Print a space instead
            JSR    GetNameSlot     ; followed the file/subdir name
:loop       INY
            LDA    (fnamePtr),Y
            JSR    PrtChar
            CPY    fnameLen
            BCC    :loop

PrtBlnk     LDA    #" "
            BNE    PrtAsIs         ;Always

HomeCursor  LDA    #$99            ;ctrl-Y
PrtChar     ORA    #$80
PrtAsIs     JMP    COUT

ReadEntry   JSR    GoPro
            DB     $CA
            DA     RdPBlk
            RTS

*-------------------------------------------------
* Data area

helpStr     ASC    "RETURN: Select | TAB: Chg Vol | ESC: "
            ASC    "Back"
            DB     $00

FolderIcon  DB     $0F             ;Set Inverse Display mode
            DB     $1B             ;Enable MouseText Mapping
            DB     $D8             ;MouseText chars
            DB     $D9
            DB     $18             ;Disable MouseText Mapping
            DB     $0E             ;Set Normal Display mode
            DB     $00             ;end of string

OpenPBlk    DB     $03
            DA     pnBuf
            DA     P8IOBuf
OpenRef     DB     $00

ClsPBlk     DB     $01
            DB     $00

OLinPBlk    DB     $02
OLUnit      DB     $60
            DA     pnBuf+1

SPfxPBlk    DB     $01
            DA     pnBuf

RdPBlk      DB     $04
ReadRef     DB     $01
            DA     entryBuf
                                   ;RdReqLen DW 0
RdReqLen    DB     0               ;Overflow