.PROC IPL
  .INCLUDE "rompac.s"
.ENDPROC

.SEGMENT "APP"
  LDA #<STR_HELLO
  LDX #>STR_HELLO
  JSR IPL::MON::PRT_STR
  BRK
STR_HELLO: .ASCIIZ "HELLO,WORLD"

