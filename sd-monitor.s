; --- SD-MONITOR ---
; SPIそしてSDカードの実装のためのデバッグ環境としてのモニタ
; MIKBUGを参考にアレンジ
; L ロード（LOAD）
; G 実行（GOTO TARGET PROGRAM）
; M メモリ操作（MEMORY CHANGE）
; P ダンプ出力（PRINT/PUNCH DUMP）
; R レジスタ表示（DISPLAY CONTENTS OF TARGET STACK、AXYレジスタは非スタック領域に持っている）
;     aAA xXX yYY fFF pPCPC sSS

; 変更履歴
; V.02 令和03年12月05日 UART受信をリングバッファ式にして、ソフトフロー制御実装

; 略語統一
; PRT=PRINT,PUT
; INPUT
; BYT=BYTE
; NIB=NIBBLE
; CNT=COUNT,COUNTER,ちなつ
; CTRL=CONTROL
; RD=READ
; WR=WRITE

; --- アドレス定義 ---

; UART
UARTBASE = $E000
UART_RX = UARTBASE
UART_TX = UARTBASE
UART_STATUS = UARTBASE+1
UART_COMMAND = UARTBASE+2
UART_CONTROL = UARTBASE+3

; VIA
VIABASE = $E200
PORTB = VIABASE
PORTA = VIABASE+1
DDRB = VIABASE+2
DDRA = VIABASE+3
IFR = VIABASE+$D

; YMZ
YMZBASE = $E400

; CRTC
CRTCBASE = $E600


; アプリケーションRAM領域（ゼロページ）
ZP_RAMBASE = $0000
A1L = ZP_RAMBASE  ; Apple][式の汎用レジスタ扱い
A1H = ZP_RAMBASE+1
A2L = ZP_RAMBASE+2
A2H = ZP_RAMBASE+3
A3L = ZP_RAMBASE+4
A3H = ZP_RAMBASE+5
A4L = ZP_RAMBASE+6
A4H = ZP_RAMBASE+7
A5L = ZP_RAMBASE+8
A5H = ZP_RAMBASE+9

; モニタRAM領域（ゼロページ） さかさまに取っていくのでHLの順に注意
MON_ZP_RAMBASE = $00FF
ADDR_INDEX_H = MON_ZP_RAMBASE
ADDR_INDEX_L = MON_ZP_RAMBASE-1  ; 各所で使うので専用
ZP_INPUT_BF_WR_P = MON_ZP_RAMBASE-2
ZP_INPUT_BF_RD_P = MON_ZP_RAMBASE-3
ZP_INPUT_BF_LEN = MON_ZP_RAMBASE-4

; UART受信用リングバッファ
INPUT_BF_BASE = $0200

; モニタRAM領域
MON_RAMBASE = $0300
SP_SAVE = MON_RAMBASE ; BRK時の各レジスタのセーブ領域。
A_SAVE = MON_RAMBASE+1
X_SAVE = MON_RAMBASE+2
Y_SAVE = MON_RAMBASE+3
A1L_SAVE = MON_RAMBASE+4
A1H_SAVE = MON_RAMBASE+5
A2L_SAVE = MON_RAMBASE+6
A2H_SAVE = MON_RAMBASE+7
A3L_SAVE = MON_RAMBASE+8
A3H_SAVE = MON_RAMBASE+9
A4L_SAVE = MON_RAMBASE+10
A4H_SAVE = MON_RAMBASE+11
A5L_SAVE = MON_RAMBASE+12
A5H_SAVE = MON_RAMBASE+13
LOAD_CKSM = MON_RAMBASE+14
LOAD_BYTCNT = MON_RAMBASE+15
T1_IRQ_VEC = MON_RAMBASE+16 ; 2byte アプリケーションが用意するタイマ割り込み処理のベクタ
UART_IRQ_VEC = MON_RAMBASE+18 ; 2byte アプリケーションによってとび先を変えられる、UART割り込み処理のベクタ

; アプリケーションRAM領域
APP_RAMBASE = $0400

; --- 定数定義 ---
; UART COMMAND
; PMC1/PMC0/PME/REM/TIC1/TIC0/IRD/DTR
; 全てゼロだと「エコーオフ、RTSオフ、割り込み有効、DTRオフ」
RTS_ON =    %00001000
ECHO_ON =   %00010000
RIRQ_OFF =  %00000010
DTR_ON =    %00000001
; 使える設定集
UARTCMD_WELLCOME = RTS_ON|DTR_ON
;UARTCMD_WELLCOME = RTS_ON|DTR_ON|RIRQ_OFF
UARTCMD_BUSY = DTR_ON
UARTCMD_DOWN = RIRQ_OFF

; LCD PIN割り当て
E   = %10000000
RW  = %01000000
RS  = %00100000

STACK = $FF ; モニタもアプリも普通にここから積み上げていこう？
EOT = $04 ; EOFでもある
XON = $11
XOFF = $13

; --- リセット ---

  .ORG $E000
  .ORG $F000

RESET:

; --- LCD初期化 ---
  LDA #%11111111  ; Set all pins on port B to output
  STA DDRB
  LDA #%11100000  ; Set top 3 pins on port A to output
  STA DDRA

  LDA #%00111000  ; Set 8-bit mode; 2-line display; 5x8 font
  JSR LCD_INST
  LDA #%00001110  ; Set Display on; cursor on; blink off
  JSR LCD_INST
  LDA #%00000110  ; Increment and shift cursor; dont shift display
  JSR LCD_INST
  LDA #%00000001  ; Clear display
  JSR LCD_INST

; --- UART初期化 ---
  LDA #$00
  STA UART_STATUS
  LDA #UARTCMD_WELLCOME
  STA UART_COMMAND
  ; SBN/WL1/WL0/RSC/SBR3/SBR2/SBR1/SBR0
  LDA #%00011011 ; 1stopbit,word=8bit,rx-rate=tx-rate,xl/512
  STA UART_CONTROL

; --- UART受信リングバッファのリセット ---
  LDA #0
  STA ZP_INPUT_BF_LEN
  STA ZP_INPUT_BF_RD_P
  STA ZP_INPUT_BF_WR_P

; --- デフォルトベクタ設定 ---
; UART割り込み処理
  LDA #<IRQ_UART
  STA UART_IRQ_VEC
  LDA #>IRQ_UART
  STA UART_IRQ_VEC+1

; --- スタックの初期化 --
  LDX #STACK
  TXS
  LDA #>APP_RAMBASE
  PHA       ; アプリケーション開始ベクタ上位
  LDA #<APP_RAMBASE
  PHA       ; アプリケーション開始ベクタ下位
  PHA       ; フラグレジスタ初期値
  TSX       ; たぶん保持しとくべきSPLは$FF-3
  STX SP_SAVE

  CLD
  CLI

; --- LCDにHelloWorld表示（生存確認） ---
  LDX #0          ; Setup Index X
PRT_SEIZON:
  LDA MESSAGE,X
  BEQ CTRL        ; Branch if EQual(zeroflag=1 -> A=null byte)
  JSR PRT_CHAR_LCD
  INX
  JMP PRT_SEIZON

; *
; --- COMMAND CONTROL ---
; *
CTRL:
  LDA #<NEWLINE
  LDX #>NEWLINE
  JSR PRT_STR
  JSR INPUT_CHAR_UART
  JSR PRT_S
  CMP #"L"
  BEQ LOAD
  CMP #"M"
  BEQ CHANGE
  CMP #"R"
  BNE CTRL1
  JMP PRTREG
CTRL1:
  CMP #"S" ; リセットボタン押すのめんどいとき用
  BEQ RESET
  CMP #"G"
  BNE CTRL

; --- 状態を復帰して飛ぶ ---
; SP復帰
  LDX SP_SAVE
  TXS
; 汎用ZP復帰
  LDA A1L_SAVE
  STA A1L
  LDA A1H_SAVE
  STA A1H
  ; ここでA2L～A5Hを復帰（サボってる）
; レジスタ復帰
  LDA A_SAVE
  LDX X_SAVE
  LDY Y_SAVE
  RTI ; GO

; *
; --- メモリ参照&変更 ---
; *
CHANGE:
  JSR BUILD_ADDR
  JMP CHANGE51
CHANGEINC:
  INC ADDR_INDEX_L
  BNE CHANGE51
  INC ADDR_INDEX_H
CHANGE51:
  LDA #<NEWLINE
  LDX #>NEWLINE
  JSR PRT_STR
  LDA ADDR_INDEX_H
  JSR PRT_BYT ;print high addr
  LDA ADDR_INDEX_L
  JSR PRT_BYT ;print low addr
  JSR PRT_S
  LDY #$0
  LDA (ADDR_INDEX_L),Y   ;Zero Page Indirect Indexed with Y
  JSR PRT_BYT ;print old data
  JSR PRT_S
  JSR INPUT_CHAR_UART
  CMP #$20
  BNE CHANGEINC ;not space
  JSR INPUT_BYT ;input new data
  LDY #$0
  STA (ADDR_INDEX_L),Y   ;Zero Page Indirect Indexed with Y
  CMP (ADDR_INDEX_L),Y
  BEQ CHANGEINC ; did change
HATENA:
  LDA #"?"
  JSR PRT_CHAR_UART
MODORU:
  JMP CTRL

; *
; --- モトローラS形式でロード ---
; *
LOAD:
  JSR PRT_LF ; Lコマンド開始時改行
LOAD_CHECKTYPE:
  JSR INPUT_CHAR_UART
  CMP #"S"
  BNE LOAD_CHECKTYPE  ; 最初の文字がSじゃないというのはありえないが
  JSR INPUT_CHAR_UART
  CMP #"9"
  BEQ LOAD_SKIPLAST  ; 最終レコード
  CMP #"1"
  BNE LOAD_CHECKTYPE  ; S1以外のレコードはどうでもいい
  LDA #0
  STA LOAD_CKSM
  JSR INPUT_BYT
  SEC
  SBC #$2
  STA LOAD_BYTCNT

; --- アドレス部 ---
  JSR BUILD_ADDR

; --- データ部 ---
LOAD_STORE_DATA
  JSR INPUT_BYT
  DEC LOAD_BYTCNT
  BEQ LOAD_ZEROBYT_CNT ; 全バイト読んだ
  LDY #$0
  STA (ADDR_INDEX_L),Y   ;Zero Page Indirect Indexed with Y
  INC ADDR_INDEX_L
  BNE LOAD_SKIPINC
  INC ADDR_INDEX_H
LOAD_SKIPINC:
  JMP LOAD_STORE_DATA

; --- ゼロバイトを数える ---
LOAD_ZEROBYT_CNT:
  JSR PRT_LF    ; ここがレコード端のはずだから改行すると見やすい
  INC LOAD_CKSM
  BEQ LOAD_CHECKTYPE  ; チェックサムが256超えたらOK
  JMP HATENA  ; おかしいのでハテナ出して終了

; --- 最終レコードを読み飛ばす ---
LOAD_SKIPLAST:
  JSR INPUT_CHAR_UART
  CMP #EOT
  BNE LOAD_SKIPLAST
  JMP CTRL

; *
; --- 入力から2バイトアドレスを得てメモリに格納する ---
; *
BUILD_ADDR:
  JSR INPUT_BYT
  STA ADDR_INDEX_H
  JSR INPUT_BYT
  STA ADDR_INDEX_L
  RTS

; *
; --- Aレジスタに二桁のhexを値として取り込み ---
; *
INPUT_BYT:
  JSR INPUT_CHAR_UART
  CMP #$0A
  BEQ HATENA
  JSR NIB_DECODE
  ASL
  ASL
  ASL
  ASL
  STA A1L
  JSR INPUT_CHAR_UART
  JSR NIB_DECODE
  ORA A1L
  STA A1L
  CLC
  ADC LOAD_CKSM ; Sレコードのチェックサム計算
  STA LOAD_CKSM
  LDA A1L
  RTS

; *
; --- Aレジスタを二桁のhexで表示 ---
; 何も汚さない
; *
PRT_BYT:
  PHA
  LSR
  LSR
  LSR
  LSR
  JSR PRHEXZ
  PLA
PRHEX:
  AND #$0F
PRHEXZ:
  ORA #$30
  CMP #$3A
  BCC PRT_BYT1
  ADC #$06
PRT_BYT1:
  JSR PRT_CHAR_UART
  RTS

; *
; --- Aレジスタの一文字をNibbleとして値にする ---
; *
NIB_DECODE:
  CMP #"0"
  BMI NIB_ERR
  CMP #"9"+1
  BPL NIB_HEX
  SEC
  SBC #"0"
  RTS
NIB_HEX:
  CMP #"A"
  BMI NIB_ERR
  CMP #"F"+1
  BPL NIB_ERR
  SEC
  SBC #"A"-$0A
  RTS
NIB_ERR:
  BRK

; *
; --- 文字列をUARTで出力する ---
; 先頭アドレスを指定する
; *
PRT_STR:
  STA A1L
  STX A1H
  LDY #$00
PRT_STR_LOOP:
  LDA (A1L),Y   ;Zero Page Indirect Indexed with Y
  BEQ PRT_STR_EXIT
  JSR PRT_CHAR_UART
  INY
  JMP PRT_STR_LOOP
PRT_STR_EXIT:
  RTS

; *
; --- スペースを出力 ---
; *
PRT_S:
  PHA
  LDA #" "
  JSR PRT_CHAR_UART
  PLA
  RTS

; *
; --- 改行を出力 ---
; *
PRT_LF:
  PHA
  LDA #$A
  JSR PRT_CHAR_UART
  PLA
  RTS

; hang until we have a char, return it via A reg.
;INPUT_CHAR_UART:
;  LDA UART_STATUS
;  AND #$08
;  BEQ INPUT_CHAR_UART
;  LDA UART_RX
;  CMP #$0A
;  BEQ ICU1
;  JSR PRT_CHAR_UART ; echo
;ICU1:
;  RTS

; バッファから一文字をAレジスタに取り出す。無ければ待つ。
; Xを壊す
INPUT_CHAR_UART:
  LDA #0
  CMP ZP_INPUT_BF_LEN
  BEQ INPUT_CHAR_UART   ; バッファに何もないなら来るまで待つ
  LDX ZP_INPUT_BF_RD_P  ; インデックス
  LDA INPUT_BF_BASE,X   ; バッファから読む、ここからRTSまでA使わない
  CMP #$0A              ;
  BEQ SKIP_ECHO         ; 改行文字はエコーしない方が融通が利く
  JSR PRT_CHAR_UART     ; ECHO
SKIP_ECHO:
  INC ZP_INPUT_BF_RD_P  ; 読み取りポインタ増加
  DEC ZP_INPUT_BF_LEN   ; 残りバッファ減少
  LDX ZP_INPUT_BF_LEN
  CPX #$80              ; LEN - $80
  BCS SKIP_RTSON
; RTS再開
  PHA
  LDA #XON
  JSR PRT_CHAR_UART
  PLA
SKIP_RTSON:
  RTS

; 通常より待ちの短い一文字送信。XOFF送信用。
; 時間計算をしているわけではないがとにかくこれで動く
PRT_CHAR_SMALLDELAY:
  STA UART_TX
  PHA
  TXA
  PHA
  LDX #$80
SMALLDELAY:
  NOP
  NOP
  DEX
  BNE SMALLDELAY
  PLA
  TAX
  PLA ; restore X, A
  RTS

; print A reg to UART
PRT_CHAR_UART:
  ;CMP UART_STATUS ; これいらんだろ
  STA UART_TX
DELAY_6551:
  PHA ; push A,X
  TXA
  PHA
DELAY_LOOP:
  LDX #$D0
DELAY_1:
  NOP
  NOP
  NOP
  DEX
  BNE DELAY_1
  PLA
  TAX
  PLA ; restore X,A
DELAY_DONE:
  RTS

LCD_WAIT:
  PHA             ; Push A
  LDA #%00000000  ; Port B is input
  STA DDRB
LCDBUSY:
  LDA #RW
  STA PORTA
  LDA #(RW | E)
  STA PORTA
  LDA PORTB       ; Read data from LCD
  AND #%10000000  ; if busy then %10000000 -> not zero -> zeroflag:0
  BNE LCDBUSY     ; Branch if Not Equal(zeroflag=0)

  LDA #RW
  STA PORTA
  LDA #%11111111  ; Port B is output
  STA DDRB
  PLA             ; Pull A
  RTS

LCD_INST:
  JSR LCD_WAIT
  STA PORTB
  LDA #0          ; Clear RS/RW/E bits
  STA PORTA
  LDA #E          ; Enable up-down
  STA PORTA
  LDA #0          ; Clear (RS/RW)/E bits
  STA PORTA
  RTS

PRT_CHAR_LCD:
  JSR LCD_WAIT
  STA PORTB
  LDA #RS         ; Only RegSelect HIGH
  STA PORTA
  LDA #(RS | E)   ; RegSelect and Enable HIGH
  STA PORTA
  LDA #RS         ; Enable LOW
  STA PORTA
  RTS


NMI:
  RTI

; *
; --- UART割り込み処理 ---
; *
IRQ_UART:
  ; Aはすでにプッシュされている
  TXA
  PHA
; すなわち受信割り込み
  LDA UART_RX          ; UARTから読み取り
  LDX ZP_INPUT_BF_WR_P ; バッファの書き込み位置インデックス
  STA INPUT_BF_BASE,X ; バッファへ書き込み
  LDX ZP_INPUT_BF_LEN
  CPX #$BF             ; バッファが3/4超えたら停止を求める
  BCC SKIP_RTSOFF ; A < M BLT
; バッファがきついのでXoff送信
  LDA #XOFF
  JSR PRT_CHAR_SMALLDELAY
  ;STA UART_TX
SKIP_RTSOFF:
  CPX #$FF  ; バッファが完全に限界なら止める
  BNE SKIP_BRK
  BRK
SKIP_BRK
; ポインタ増加
  INC ZP_INPUT_BF_WR_P
  INC ZP_INPUT_BF_LEN
EXIT_UART_IRQ
  PLA
  TAX
  PLA
  CLI
  RTI

; *
; --- 割り込み処理 ---
; *
IRQ:
  SEI ; RTI前に必ず切ること

; --- 外部割込み判別 ---
  PHA ; まだXY使用禁止
; UART
  LDA UART_STATUS
  ;ROL ; キャリーにIRQが
  ;BCC CHECK_VIA_IRQ
  BIT #%00001000
  BEQ CHECK_VIA_IRQ ; bit3の論理積がゼロ、つまりフルじゃない
  JMP (UART_IRQ_VEC) ; ベクタに飛ぶ（デフォルトで設定されているが変更されうる）
; VIA
CHECK_VIA_IRQ:
  LDA IFR ; 割り込みフラグレジスタ読み取り
  ROL ; キャリーにIRQが
  ROL ; キャリーにTIMER1が
  BCC IRQ_DEBUG ; TIMER1割り込みじゃないならとりあえず無視
  JMP (T1_IRQ_VEC) ; 所定のベクトルにタイマー割り込み（アプリケーションですきにしてよい）

; --- モニタに落ちる ---
IRQ_DEBUG:
  PLA
  STA A_SAVE
  STX X_SAVE
  STY Y_SAVE
  LDA A1L
  STA A1L_SAVE
  LDA A1H
  STA A1H_SAVE
  ; ここでA2L～A5Hを退避（サボってる）
  TSX
  STX SP_SAVE ; save targets stack poi

; --- プログラムカウンタを減算 ---
  LDX SP_SAVE
  INX
  INX ; SP+2=PCL
  LDA #$1
  CMP $0100,X ; PCLと#$1の比較
  BCC SKIPHDEC
  BEQ SKIPHDEC
  INX
  DEC $0100,X ; PCH--
  DEX
SKIPHDEC:
  DEC $0100,X ; PCL--
  ; DEC $0100,X ; PCL--
  ; 二回引くとBRK命令そのものを指すが、また実行することを考えると一回でいいのかな

; --- レジスタ情報を表示 ---
PRTREG:  ; print contents of stack

; 表示中にさらにBRKされると分かりづらいので改行
  LDA #<NEWLINE
  LDX #>NEWLINE
  JSR PRT_STR

; A
  JSR PRT_S
  LDA #"a"
  JSR PRT_CHAR_UART

  LDA A_SAVE ; Acc reg
  JSR PRT_BYT

; X
  JSR PRT_S
  LDA #"x"
  JSR PRT_CHAR_UART

  LDA X_SAVE  ; X reg
  JSR PRT_BYT

; Y
  JSR PRT_S
  LDA #"y"
  JSR PRT_CHAR_UART

  LDA Y_SAVE  ; Y reg
  JSR PRT_BYT

; Flag
  JSR PRT_S
  LDA #"f"
  JSR PRT_CHAR_UART

  LDX SP_SAVE ; Flags
  INX ; SP+1=F
  LDA $0100,X
  JSR PRT_BYT

; PC
  JSR PRT_S
  LDA #"p"
  JSR PRT_CHAR_UART

  INX         ; SP+3=PCH
  INX
  LDA $0100,X
  JSR PRT_BYT

  DEX         ; PCL
  LDA $0100,X
  JSR PRT_BYT

  JSR PRT_S
  LDA #"s"
  JSR PRT_CHAR_UART

; SP
  LDA SP_SAVE     ; stack pointer
  JSR PRT_BYT
  CLI
  JMP CTRL

NEWLINE: .ASCIIZ $A,"*"
MESSAGE: .ASCIIZ "SD-Monitor  V.02","                        ","      for FxT-65"

  .ORG $FFFA
  .WORD NMI
  .WORD RESET
  .WORD IRQ
