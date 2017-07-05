***********************************************************
* Global Data

ownersBlock DW     $0000
ownersEnt   DB     $00
ownersLen   DB     $00

*-------------------------------------------------
* Part of volume dir header

h_creDate   DW     $0000           ;Directory creation date
            DW     $0000           ;Directory creation time
            DB     $00             ;Version under which this directory was created
            DB     $00             ;Earliest version that it's compatible with
h_attr      DB     $00             ;Attributes (protect bit, etc.)
h_entLen    DB     $00             ;Length of each entry in this dir
h_maxEnt    DB     $00             ;Maximum # of entries per block
h_fileCnt   DW     $0000           ;Current # of files in this dir
h_bitMap    DW     $0000           ;Disk Addr of first allocation bit map
h_totBlk    DW     $0000           ;Total number of blocks on this unit

d_dev       DB     $00             ;Device number of this directory entry
d_head      DW     $0000           ;Disk Addr of <sub> directory header
d_entBlk    DW     $0000           ;Disk Addr of block which contains this entry
d_entNum    DB     $00             ;Entry number within block

*-------------------------------------------------
* Layout of file entry

d_file      EQU    *
d_stor      EQU    *-d_file
            DB     $00             ;storage type * 16 + file name length
            DS     15,0            ;file name
d_fileID    EQU    *-d_file
            DB     $00             ;User's identification byte
d_first     EQU    *-d_file
            DW     $0000           ;First block of file
d_usage     EQU    *-d_file
            DW     $0000           ;# of blks currently allocated to this file
d_eof       EQU    *-d_file
            DB     0,0,0           ;Current end of file marker
d_creDate   EQU    *-d_file
            DW     $0000           ;date of file's creation
d_creTime   EQU    *-d_file
            DW     $0000           ;time of file's creation
d_sosVer    EQU    *-d_file
            DB     $00             ;SOS version that created this file
d_comp      EQU    *-d_file
            DB     $00             ;Backward version compatablity
d_attr      EQU    *-d_file
            DB     $00             ;'protect', read/write 'enable' etc.
d_auxID     EQU    *-d_file
            DW     $0000           ;User auxillary identification
d_modDate   EQU    *-d_file
            DW     $0000           ;File's last modification date
d_modTime   EQU    *-d_file
            DW     $0000           ;File's last modification time
d_dHdr      EQU    *-d_file
            DW     $0000           ;Header block address of file's directory

*-------------------------------------------------

scrtch      DS     4,0             ;Scratch area for allocation address conversion
oldEOF      DS     3,0             ;Temp used in w/r
oldMark     DS     3,0             ;Used by 'RdPosn' and 'Write'

xvcbPtr     DB     $00             ;Used in 'cmpvcb' as a temp 
vcbPtr      DB     $00             ;Offset into VCB table
fcbPtr      DB     $00             ;Offset into FCB table
fcbFlg      DB     $00             ;This is a flag to indicate a free FCB is available

reqL        DB     $00             ;# of free blks required
reqH        DB     $00
levels      DB     $00             ;Storage type (seedling,sapling etc)

* # of entries examined or
* used as a flag to indicate file is already open

totEnt      DB     $00             ;(0=open)
entCnt      DW     $0000           ;File count

* entries/block loop count or
* as a temp to return the refnum of a free FCB

cntEnt      DB     $00

* Free entry found flag (if > 0)
* # of 1st bitMap block with free bit on
* or bit for free

noFree      DB     $00

*-------------------------------------------------
* Variable work area

bmCnt       DB     $00             ;# in bitMap left to search
sapPtr      DB     $00
pathCnt     DB     $00             ;Pathname len
pathDev     DB     $00             ;Dev num for prefix dir header
pathBlok    DW     $0000           ;Block of prefix dir header
bmPtr       DB     $00             ;VBM byte offset in page
basVal      DB     $00             ;VBM page offset
half        DB     $00             ;VBM buf page (0 or 1)

* bit map info tables (a & b)

bmaStat     DB     $00             ;VBM flag (If $80, needs writing)
bmaDev      DB     $00             ;VBM device
bmaDskAdr   DW     $00             ;VBM blk number
bmaCurrMap  DB     $00             ;bitMap blk offset for multiblk VBM

* New mark to be positioned to for SetMark
* or new moving mark (for Read)
* or new EOF for SETEOF

tPosll      DB     $00
tPoslh      DB     $00
tPosHi      DB     $00
rwReqL      DB     $00             ;Request count (R/W etc)
rwReqH      DB     $00
nlChar      DB     $00
nlMask      DB     $00
ioAccess    DB     $00             ;Has a call been made to disk device handler?
bulkCnt     EQU    *
cmdTmp      DB     $00             ;Test refnum, time, and dskswtch for (pre)processing

bkBitFlg    DB     $00             ;Used for ReviseDir to set or clear back up bit
duplFlag    DB     $00             ;Difference between volNotFound and dupVol by synPath
vcbEntry    DB     $00             ;Pointer to current VCB entry

* xdos temporaries added....

namCnt      DB     $00             ;ONLINE: vol len - loop index

* Characters in current pathname index level or
* New pathname : index to last name

rnPtr       DB     $00
pnPtr       EQU    *               ; Old pathname: index to last name or
namPtr      DB     $00             ;ONLINE: index to data buffer
vnPtr       DB     $00             ;Old PfixPtr value
prfxFlg     DB     $00             ;Pathname fully qualified flag (if $FF)
clsFlshErr  EQU    *               ;Close-all err code
tempX       DB     $00             ;ONLINE: devcnt

* The following are used for deallocation temps.

firstBlkL   DB     $00
firstBlkH   DB     $00
storType    DB     $00
deBlock     DW     $0000           ;Count of freed blks
dTree       DB     $00             ;EOFblk # (MSB)
dSap        DB     $00             ;EOFblk # (LSB)
dSeed       DW     $0000           ;EOF byte offset into blk
topDest     DB     $00             ;EOF-master index counter
dTempX      DB     $00             ;ONLINE: devcnt

* Device table built by Online
* Also used by SetEOF to keep track
* of 8 blks to be freed at a time

deAlocBufL  DS     8,0
deAlocBufH  DS     8,0

lookList    EQU    deAlocBufL      

cBytes      DW     $0000           ;Len of path, etc
            DB     $00             ;cbytes+2 must always be zero. See "CalcMark"
bufAddrL    DB     $00
bufAddrH    DB     $00             ;Buffer allocation, getbuffr, and release buffer temps.
goAdr       DA     $0000           ;Jump vector used for indirect JMP
delFlag     DB     $00             ;Used by DeTree to know if called from delete
            DS     $FEFD-*,0
dispVect    EQU    *
            DA     CallDisp        ;Dispatcher/Selector

* This flag is set in the loader indicating
* whether the machine is a cortland

cortFlag    DB     0               ;0=>non-cortland / 1=>cortland