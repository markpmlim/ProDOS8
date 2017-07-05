***********************************************************
* ---- Added call $41 & its count - see rev note 20 --------

scNums      EQU    *
            DFB    $D3,0,0,0       ;(zeros are reserved for bfm)
            DFB    $40,$41,$00,0   ;(zero is reserved for interrupt calls)
            DFB    $80,$81,$82,$65
            DFB    $C0,$C1,$C2,$C3
            DFB    $C4,$C5,$C6,$C7
            DFB    $C8,$C9,$CA,$CB
            DFB    $CC,$CD,$CE,$CF
            DFB    $00,$D0,$D1,$D2 ;zero is non-existent.

pCntTbl     EQU    *               ;parameter counts for the calls 
            HEX    02FFFFFF
            HEX    0201FFFF
            HEX    03030004
            HEX    07010207
            HEX    0A020101
            HEX    03030404
            HEX    01010202
            HEX    FF020202

*-------------------------------------------------
* JMP table

cmdTable    EQU    *
            DA     Create
            DA     Destroy
            DA     Rename
            DA     SetInfo
            DA     GetInfo
            DA     Online
            DA     SetPrefix
            DA     GetPrefix
            DA     Open
            DA     NewLine
            DA     Read
            DA     Write
            DA     Close
            DA     Flush
            DA     SetMark
            DA     GetMark
            DA     SetEOF
            DA     GetEOF
            DA     SetBuf
            DA     GetBuf

*-------------------------------------------------
* Function bits for MLI codes $C0-$D3

Dispatch    EQU    *
            DB     prePath+preTime+0;create
            DB     prePath+preTime+1;destroy
            DB     prePath+preTime+2;rename
            DB     prePath+preTime+3;setinfo
            DB     prePath+4       ;getinfo
            DB     $05             ;volume
            DB     $06             ;setprefix, pathname moved to prefix buffer
            DB     $07             ;getprefix
            DB     prePath+8       ;open
            DB     preRef+$9       ;newline
            DB     preRef+$a       ;read
            DB     preRef+$b       ;write
            DB     preTime+$c      ;close
            DB     preTime+$d      ;flush, refnum may be zero to flush all
            DB     preRef+$e       ;setmark
            DB     preRef+$f       ;getmark
            DB     preRef+$10      ;set eof
            DB     preRef+$11      ;get eof
            DB     preRef+$12      ;set buffer address (move)
            DB     preRef+$13      ;get buffer address

*-------------------------------------------------
* Constants

dIncTbl     DB     1,0,0,2,0       ;Table to increment directory usage/EOF counts
Pass        DB     $75
XDOSver     DB     $0,0,$C3,$27,$0D,0,0,0
compat      EQU    XDOSver+1

rootStuff   DB     $0F,2,0,4
            DB     0,0,8,0

WhichBit    HEX    8040201008040201

* The following table is used in the 'Open:loop1' (posn/open). 
* Offsets into file control blocks (FCBs)

oFCBTbl     DFB    fcbFirst,fcbFirst+1,fcbBlksUsed,fcbBlksUsed+1
            DFB    fcbEOF,fcbEOF+1,fcbEOF+2

* Set/Get file info offsets
* The following with $80+ are ignored by SetInfo

InfoTabl    DFB    d_attr,d_fileID,d_auxID,d_auxID+1
            DFB    $80+d_stor,$80+d_usage,$80+d_usage+1,d_modDate
            DFB    d_modDate+1,d_modTime,d_modTime+1,d_creDate
            DFB    d_creDate+1,d_creTime,d_creTime+1

Death       ASC    '               '
            ASC    "RESTART SYSTEM-$01"
            ASC    '               '