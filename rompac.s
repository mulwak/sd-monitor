; ROMに格納されるソース群
; 直接にはこいつをアセンブルする
.ZEROPAGE
  .INCLUDE "zpmon.s"
  .INCLUDE "zpipl.s"

.SEGMENT "ROMBF100"        ; $0200~
  INPUT_BF_BASE:  .RES 256 ; UART受信用リングバッファ
  SECBF512:       .RES 512 ; SDカード用セクタバッファ

.SEGMENT "MONVAR"
  .INCLUDE "varmon.s"
.SEGMENT "IPLVAR"
  .INCLUDE "varipl.s"

.SEGMENT "ROMCODE"
  .PROC MON
    .INCLUDE "sd-monitor.s"
  .ENDPROC
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
.SEGMENT "APPBF100"

