 lst off
*-------------------------------------------------
* This make file will generate the P8 SYS file
* automatically.
*
* Requirements for Assembly:
* Merlin16+ v4.08

 USES mli.src/mli.macs
 USES 8:Tool.Equates:E16.Memory
 USES 8:Tool.Equates:E16.GSOS
 TR ON
 EXP OFF
 TYPE SYS
; lst on
; lst file,/blank/p8.lst
 PUT mli.src/Equates
 PUT mli.src/ProLdr
 PUT mli.src/DevSrch
 PUT mli.src/Reloc
 PUT mli.src/RAM1
 PUT mli.src/RAM2
 PUT mli.src/ROM
 PUT mli.src/Globals
 PUT mli.src/TClock
 PUT mli.src/CClock
 PUT mli.src/XDosMLI
 PUT mli.src/BFMgr
 PUT mli.src/Create
 PUT mli.src/FndFil
 PUT mli.src/NewFndVol
 PUT mli.src/Alloc
 PUT mli.src/PosnOpen
 PUT mli.src/ReadWrite
 PUT mli.src/CloseEOF
 PUT mli.src/Destroy
 PUT mli.src/DeTree
 PUT mli.src/MemMgr
 PUT mli.src/DataTbls
 PUT mli.src/WrkSpace
 PUT mli.src/RAM0
 PUT mli.src/XRW1
 PUT mli.src/XRW2
 PUT mli.src/SEL0
 PUT mli.src/SEL1
 PUT mli.src/SEL2
 SAV P8
 lst off