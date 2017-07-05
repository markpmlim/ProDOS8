*-------------------------------------------------
* Disassembler: The Flaming Bird Disassembler
* Assembler : Merlin16+
* Merlin16+ is chosen because it can assemble
* 65816 opcodes unlike EdAsm (ProDOS) which is
* an 8-bit assembler. Furthermore, local labels
* may be used; that should ease the need to
* create trivial labels.
* NB. Merlin16+ defaults to case-sensitive labels
* & using blank lines should improve readibility.
* Most of the comments and labels are from the
* source code of ProDOS v1.7
* Whenever possible a more descriptive label is
* used in place of the original.
*-------------------------------------------------
* Global Equates

MSLOT       EQU    $07F8
KBD         EQU    $C000
CLR80COL    EQU    $C000           ;Disable 80-column memory mapping (Write)
SET80COL    EQU    $C001           ;Enable 80-column memory mapping (WR-only)
RDMAINRAM   EQU    $C002
RDCARDRAM   EQU    $C003
WRMAINRAM   EQU    $C004           ;Write data to main ram
WRCARDRAM   EQU    $C005           ;Write data to card ram
SETSTDZP    EQU    $C008           ;Enable regular ZP,STK,LC
SETALTZP    EQU    $C009           ;Enable alternate ZP,STK,LC
SETINTC3ROM EQU    $C00A           ;Internal 80-col card ROM
SETSLOTC3ROM       EQU             $C00B ;External slot 3 ROM
CLR80VID    EQU    $C00C           ;Disable 80 column hardware.
CLRALTCHAR  EQU    $C00E           ;Switch in primary character set.
KBDSTROBE   EQU    $C010
RD80COL     EQU    $C018
NEWVIDEO    EQU    $C029
SPKR        EQU    $C030
TXTSET      EQU    $C051
TXTPAGE1    EQU    $C054
TXTPAGE2    EQU    $C055
STATEREG    EQU    $C068           ;Cortland memory state register
ROMIN2      EQU    $C081           ;swap rom in w/o w-prot ram
RDROM2      EQU    $C082           ;swap rom in, write protect ram
LCBANK2     EQU    $C083           ;Enable 2nd bank of LC
LCBANK1     EQU    $C08B           ;Enable 1st bank of LC
CLRROM      EQU    $CFFF

* 80 col card subroutines

AuxMove     EQU    $C311           ;monitor move data routine
Xfer        EQU    $C314           ;monitor XFER control

* Apple // Monitor subroutines

ROMIrq      EQU    $FA41           ;monitor rom irq entry
Init        EQU    $FB2F           ;Text pg1;text mode;sets 40/80 col
SETTXT      EQU    $FB39
TABV        EQU    $FB5B
SETPWRC     EQU    $FB6F
VERSION     EQU    $FBB3
BELL1       EQU    $FBDD
HOME        EQU    $FC58
CLREOL      EQU    $FC9C
RDKEY       EQU    $FD0C
CROUT       EQU    $FD8E
COUT        EQU    $FDED
IDroutine   EQU    $FE1F           ;IIgs ID routine
SetInv      EQU    $FE80
SetNorm     EQU    $FE84           ;Normal white text on black backround.
SetKBD      EQU    $FE89           ;Does an IN#1.
SetVid      EQU    $FE93           ;Puts COUT1 in CSW.
BELL        EQU    $FF3A
OLDRST      EQU    $FF59           ;monitor reset entry

* GS/OS vectors/flags

GSOS        EQU    $E100A8
GSOS2       EQU    $E100B0
OS_BOOT     EQU    $E100BD

inBuf       EQU    $0200           ;Input buffer
pnBuf       EQU    $0280           ;pathname buffer
EnterCard   EQU    $0200           ;AuxMem
RAMdest     EQU    $0200           ;AuxMem
RAMsrc      EQU    $5100           ;Load addr
LCdest      EQU    $FF00           ;Execution addr of RAM disk handler

* Page 3 vectors

SOFTEV      EQU    $03F2
PWREDUP     EQU    $03F4
NMI         EQU    $03FB
PassIt      EQU    $03ED

*                                         load addr    exec addr     Description
*=========================================================================================
MLI_0       EQU    $2000           ;$2000-$2c7F  $2000-$2c7F  MLI loader/relocater
RAM_1       EQU    MLI_0+$C80      ;$2c80-$2cff  $2c80-$2cbc  installer for /RAM
RAM_2       EQU    RAM_1+$080      ;$2d00-$2d8f  $ff00-$ff8f  /RAM driver in main lc
MLI_3       EQU    RAM_2+$09B      ;$2d9b-$2dff  $ff9b-$ffff  interrupts
MLI_1       EQU    MLI_3+$065      ;$2E00-$2eff  $bf00-bfff   global page
TCLOCK_0    EQU    MLI_1+$100      ;$2f00-$2f7f  $d742-$d7be  TCLOCK driver
CCLOCK_0    EQU    TCLOCK_0+$080   ;$2f80-$2fff  $d742-$d7be  CCLOCK driver
MLI_2       EQU    CCLOCK_0+$080   ;$3000-$4fff  $de00-$feff  MLI itself
RAM_0       EQU    MLI_2+$2100     ;$5100-$52ff  $0200-$03ff  /RAM driver in aux mem
XRW_0       EQU    RAM_0+$200      ;$5300-$59FF  $d000-$d6ff  disk core routines
SEL_0       EQU    XRW_0+$700      ;$5A00-$5cff  $1000-$12ff  original dispatcher
SEL_1       EQU    SEL_0+$300      ;$5d00-$5fff  $1000-$12ff  better bye dispatcher
SEL_2       EQU    SEL_1+$300      ;$6000-$2c7F  $1000-$12ff  gs/os dispatcher

* ProDOS 8 equates

ABuf        EQU    $0C00           ;Temporary buffer
VBlock1     EQU    $0E00           ;Where the Vol Dir goes
VolNameStr  EQU    $0F00           ;Use by SEL2 (p-string)
DispAdr     EQU    $1000           ;Execution address of dispatcher
RWTS        EQU    $D000           ;Addr of Disk ][ driver
IOBuf       EQU    $1C00
Srce        EQU    $2C80
LCSrc       EQU    Srce+$80
LCDest      EQU    $FF00
ClockBegin  EQU    $D742           ;Entry address of clock

LoadIntrp   EQU    $0800           ;Execution addr of load interpreter
orig        EQU    $D700
orig1       EQU    $DE00
Globals     EQU    $BF00           ;ProDOS's global page
IntHandler  EQU    $FF9B           ;Start of interrupt handler
pathBuf     EQU    orig
fcb         EQU    orig+$100       ;File Control Blocks
vcb         EQU    orig+$200       ;Volume Control Blocks
bmBuf       EQU    orig+$300       ;Bitmap buffer
genBuf      EQU    pathBuf+$500    ;General purpose buffer
*
* Constants
*
preTime     EQU    $20             ;command needs current date/time stamp
preRef      EQU    $40             ;command requires fcb address and verification
prePath     EQU    $80             ;command has pathname to preprocess
*
* volume status constants (bits)
*
* file status constants
*
dataAloc    EQU    $1              ;data block not allocated.
idxAloc     EQU    $2              ;index not allocated
topAloc     EQU    $4              ;top index not allocated
storTypMod  EQU    $8              ;storage type modified
useMod      EQU    $10             ;file usage modified
eofMod      EQU    $20             ;end of file modified
dataMod     EQU    $40             ;data block modified
idxMod      EQU    $80             ;index block modified
fcbMod      EQU    $80             ;has fcb/directory been modified? (flush)
*
* header index constants
*
hNamLen     EQU    $0              ;header name length (offset into header)
hName       EQU    $1              ;header name
hPassEnable EQU    $10             ;password enable byte
hPassWord   EQU    $11             ;encoded password
hCreDate    EQU    $18             ;header creation date
* hCreTime EQU $1A ;header creation time
hVer        EQU    $1C             ;sos version that created directory
hComp       EQU    $1D             ;backward compatible with sos version
hAttr       EQU    $1E             ;header attributes- protect etc.
hEntLen     EQU    $1F             ;length of each entry
hMaxEnt     EQU    $20             ;maximum number of entries/block
hFileCnt    EQU    $21             ;current number of files in directory
hOwnerBlk   EQU    $23             ;owner's directory disk address
hOwnerEnt   EQU    $25             ;owner's directory entry number
hOwnerLen   EQU    $26             ;owner's directory entry length
vBitMap     EQU    hOwnerBlk
vTotBlk     EQU    hOwnerEnt       ;(used for root directory only)
*
* Volume Control Block index constants
*
vcbSize     EQU    $20             ;Current VCB is 32 bytes per entry (ver 0)
vcbNamLen   EQU    0               ;Volume name length byte
vcbName     EQU    1               ;Volume name
vcbDevice   EQU    $10             ;Volume's device #
vcbStatus   EQU    $11             ;Volume status. (80=files open. 40=disk switched.)
vcbTotBlks  EQU    $12             ;Total blocks on this volume
vcbFreeBlks EQU    $14             ;Number of unused blocks
vcbRoot     EQU    $16             ;Root directory (disk) address
*vcbBitMapOrg EQU $18 ;map organization (not supported by v 0)
*vcbBitMapBuf EQU $19 ;bit map buf num
vcbBitMap   EQU    $1A             ;First (disk) address of bitmap(s)
vcbCurrBitMap      EQU             $1C ;Rel addr of bitmap w/space  (add to vcbBitMap)
*vcbmnum EQU $1D ; relative bit map currently in memory
vcbOpenCnt  EQU    $1E             ;Current number of open files.
*vcbaddr EQU $1F reserved
*
* File Control Block index constants
*
fcbSize     EQU    $20             ;Current FCB is 32 bytes per entry (ver 0)
fcbRefNum   EQU    0               ;file reference number (position sensitive)
fcbDevNum   EQU    1               ;device (number) on which file resides
*fcbHead EQU 2 ;block address of file's directory header
*fcbDirBlk EQU 4 ;block address of file's directory
fcbEntNum   EQU    6               ;file entry number within dir block
fcbStorTyp  EQU    7               ;storage type - seed, sapling, tree, etc.
fcbStatus   EQU    8               ;status - index/data/eof/usage/type modified.
fcbAttr     EQU    9               ;attributes - read/write enable, newline enable.
fcbNewLin   EQU    $A              ;new line terminator (all 8 bits significant).
fcbFileBuf  EQU    $B              ;buffer number
fcbFirst    EQU    $C              ;first block of file (Master index/key blk)
fcbIdxBlk   EQU    $E              ;curr block address of index (0 if no index)
fcbDataBlk  EQU    $10             ;curr block address of data
fcbMark     EQU    $12             ;current file marker.
fcbEOF      EQU    $15             ;logical end of file.
fcbBlksUsed EQU    $18             ;actual number of blocks allocated to this file.
*fcbAddr EQU $1a reserved
fcbLevel    EQU    $1B             ;level at which this file was opened
fcbDirty    EQU    $1C             ;fcb marked as modified
fcbNLMask   EQU    $1F             ;NewLine enabled mask
*
* zero page stuff
*
look        EQU    $0A
apple       EQU    $0C
relocTbl    EQU    $10
idxl        EQU    $10
indrcn      EQU    $10
devID       EQU    $12
src         EQU    $12
dst         EQU    $14
cnt         EQU    $16
code        EQU    $18
endCode     EQU    $1A
WNDLFT      EQU    $20
WNDWDTH     EQU    $21
WNDTOP      EQU    $22
WNDBTM      EQU    $23
CH          EQU    $24
CV          EQU    $25
INVFLG      EQU    $32
A1          EQU    $3C             ;SOURCE OF TRANSFER
A2          EQU    $3E             ;END OF SOURCE
A3          EQU    $40
A4          EQU    $42             ;DESTINATION OF TRANSFER
Acc         EQU    $45
ErrNum      EQU    $DE
OURCH       EQU    $057B           ;80-col horizontal coord

* ProDOS block I/O equates
statCmd     EQU    $00             ;request status, no error=ready
rdCmd       EQU    $1
wrtCmd      EQU    $2
            DUM    $40
parm        DS     2,0
device      DS     1,0             ;parm+2
dhpCmd      EQU    device          ;Command from ProDOS8
unitNum     DS     1,0             ;Unit # from ProDOS 8 (DSSS 0000)
bufPtr      DS     2,0             ;512-byte user's I/O buffer
blockNum    DS     2,0             ;block # requested
            DEND
*
intCmd      EQU    dhpCmd          ;Interrupt command
*
            DUM    parm+8
zTemps      DS     2,0
tPath       EQU    zTemps
dirBufPtr   EQU    zTemps
tIndex      EQU    zTemps          ;Ptr to index blk buffer
dataPtr     DS     2,0             ;Ptr to data blk buffer
posPtr      DS     2,0             ;Position marker
userBuf     DS     2,0             ;Ptr to user's buffer
            DEND
*
* xdos parameters:
*
c_pCnt      EQU    $0              ; (count)
c_devNum    EQU    $1              ; (value)
c_refNum    EQU    $1              ; (value)
c_intNum    EQU    $1              ; (value)
c_path      EQU    $1              ;&2 (pointer)
c_isNewln   EQU    $2              ; (mask)
c_dataBuf   EQU    $2              ;&3 (value)
c_bufAdr    EQU    $2              ;&3 (address)
c_intAdr    EQU    $2              ;&3 (address)
c_mark      EQU    $2              ;->4 (value)
c_eof       EQU    $2              ;->4 (value)
c_attr      EQU    $3              ; (flags)
c_newl      EQU    $3              ; (character)
c_bufPtr    EQU    $3              ;&4 (pointer)
c_newPath   EQU    $3              ;&4 (pointer)
c_fileID    EQU    $4              ; (value)
c_reqCnt    EQU    $4              ;&5 (value)
c_blkNum    EQU    $4              ;&5 (address)
c_outRef    EQU    $5
c_auxID     EQU    $5              ;&6 (value)
c_xferCnt   EQU    $6              ;&7 (value)
c_fileKind  EQU    $7              ; (value)
c_date      EQU    $8              ;&9 (value)
c_outBlk    EQU    $8              ;&9 (count)
c_time      EQU    $a              ;&b (value)
c_modDate   EQU    $a              ;&b (value)
c_modTime   EQU    $c              ;&d (value)
c_creDate   EQU    $e              ;&f (value)
c_creTime   EQU    $10             ;&11 (value)

* Starting addresses of screen lines

SLIN04      EQU    $0600           ;4th line of screen (starting from 0)
SLIN09      EQU    $04A8
SLIN10      EQU    $0528
SLIN11      EQU    $05A8
SLIN12      EQU    $0628
SLIN13      EQU    $06A8
SLIN15      EQU    $07A8
SLIN22      EQU    $0750
SLIN23      EQU    $07D0

* Error Codes specific to ProDOS 8
* Other error codes are in the GS/OS equate file

unclaimedIntErr    EQU             $01
vcbUnusable EQU    $0A
fcbUnusable EQU    $0B
badBlockErr EQU    $0C             ;Block allocated illegally
fcbFullErr  EQU    $42
vcbFullErr  EQU    $55
badBufErr   EQU    $56