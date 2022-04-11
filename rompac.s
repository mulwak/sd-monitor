; ROMに格納されるソース群
; 直接にはこいつをアセンブルする
.INCLUDE "varmon.s"
.PROC MON
  .INCLUDE "sd-monitor.s"
.ENDPROC
.INCLUDE "varipl.s"
.INCLUDE "ipl.s"

.SEGMENT "VECTORS"
.WORD MON::NMI
.WORD MON::RESET
.WORD MON::IRQ

; 使わない可能性のあるセグメント
.SEGMENT "PREAPP"
.SEGMENT "APP"
.SEGMENT "LIB"
.SEGMENT "APPVAR"
.SEGMENT "INITDATA"

