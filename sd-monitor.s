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
; V.03 令和04年04月19日 割り込みを完全に移譲できるようにし、NMIを起動トリガに
; V.03 令和04年04月01日 IPLの付属品とし、CA65をアセンブラとする
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

; アプリケーションRAM領域
.IMPORT __APP_RUN__
APP_RAMBASE = __APP_RUN__

.INCLUDE "FXT65.inc"

; --- 定数定義 ---
; 使える設定集
UARTCMD_WELLCOME = UART::CMD::RTS_ON|UART::CMD::DTR_ON
UARTCMD_BUSY = UART::CMD::DTR_ON
UARTCMD_DOWN = UART::CMD::RIRQ_OFF

STACK = $FF ; モニタもアプリも普通にここから積み上げていこう？
EOT = $04 ; EOFでもある
XON = $11
XOFF = $13

; --- リセット ---
  ;.ORG $F000
  ;*=$F000
RESET:
; --- LCD初期化 ---
;  LDA #%11111111  ; Set all pins on port B to output
;  STA VIA::DDRB
;  LDA #%11100000  ; Set top 3 pins on port A to output
;  STA VIA::DDRA

;  LDA #%00111000  ; Set 8-bit mode; 2-line display; 5x8 font
;  JSR LCD_INST
;  LDA #%00001110  ; Set Display on; cursor on; blink off
;  JSR LCD_INST
;  LDA #%00000110  ; Increment and shift cursor; dont shift display
;  JSR LCD_INST
;  LDA #%00000001  ; Clear display
;  JSR LCD_INST

; --- UART初期化 ---
  LDA #$00                ; ステータスへの書き込みはソフトリセットを意味する
  STA UART::STATUS
  LDA #UARTCMD_WELLCOME   ; RTS_ON|DTR_ON
  STA UART::COMMAND
  LDA #%00011101          ; 1stopbit,word=8bit,rx-rate=tx-rate,xl/256
  STA UART::CONTROL       ; SBN/WL1/WL0/RSC/SBR3/SBR2/SBR1/SBR0

; --- UART受信リングバッファのリセット ---
  LDA #0
  STA ZP_INPUT_BF_LEN
  STA ZP_INPUT_BF_RD_P
  STA ZP_INPUT_BF_WR_P

; --- デフォルトベクタ設定 ---
; UART割り込み処理
  LDA #<IRQ_ROM
  STA IRQ_VEC16
  LDA #>IRQ_ROM
  STA IRQ_VEC16+1

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

; --- 設定フラグセット
  LDA #%10000000
  STA ECHO_F

  CLD
  CLI

JMP_IPL:
  JMP IPL_RESET

; --- LCDにHelloWorld表示（生存確認） ---
CTRL:
;  LDA #%00000001  ; Clear display
;  JSR LCD_INST
;  LDX #0          ; Setup Index X
;PRT_SEIZON:
;  LDA STR_MESSAGE,X
;  BEQ @EXT        ; Branch if EQual(zeroflag=1 -> A=null byte)
;  JSR PRT_CHAR_LCD
;  INX
;  BRA PRT_SEIZON
;@EXT:

; *
; --- COMMAND CONTROL ---
; *
  LDA #<STR_NEWLINE
  LDX #>STR_NEWLINE
  JSR PRT_STR
  JSR INPUT_CHAR_UART
  JSR PRT_S
  CMP #'B' ; 強制カードブート
  BNE @SKP_B
  JSR OPENINI_RDMODE
  JMP RD_BOOT_LOAD_POINT
@SKP_B:
  CMP #'S' ; リセットボタン押すのめんどいとき用
  BEQ RESET
  CMP #'L'
  BEQ LOAD
  CMP #'M'
  BEQ CHANGE
  CMP #'R'
  BNE @SKP_R
  JMP PRTREG
@SKP_R:
  CMP #'D'
  BNE @SKP_D
  JMP DUMPPAGE
@SKP_D:
  CMP #'G'
  BNE CTRL

; --- 状態を復帰して飛ぶ ---
; SP復帰
  LDX SP_SAVE
  TXS
; 汎用ZP復帰
  LDX #12-1
@LOADZRLOOP:
  LDA ZR0_SAVE,X
  STA ZR0,X
  DEX
  BPL @LOADZRLOOP
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
  LDA #<STR_NEWLINE
  LDX #>STR_NEWLINE
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
  LDA #'?'
  JSR PRT_CHAR_UART
MODORU:
  JMP CTRL

; *
; --- モトローラS形式でロード ---
; *
LOAD:
  JSR PRT_LF ; Lコマンド開始時改行
  STZ ECHO_F  ; エコーを切ったら速いかもしれない
LOAD_CHECKTYPE:
  JSR INPUT_CHAR_UART
  CMP #'S'
  BNE LOAD_CHECKTYPE  ; 最初の文字がSじゃないというのはありえないが
  JSR INPUT_CHAR_UART
  CMP #'9'
  BEQ LOAD_SKIPLAST  ; 最終レコード
  CMP #'1'
  BNE LOAD_CHECKTYPE  ; S1以外のレコードはどうでもいい
  LDA #0
  STA LOAD_CKSM
  JSR INPUT_BYT
  SEC
  SBC #$2
  STA LOAD_BYTCNT
  ; 何バイトのレコードかを表示
  ;JSR PRT_LF
  ;JSR PRT_BYT
  ;JSR PRT_LF

; --- アドレス部 ---
  JSR BUILD_ADDR

; --- データ部 ---
LOAD_STORE_DATA:
  JSR INPUT_BYT
  DEC LOAD_BYTCNT
  BEQ LOAD_ZEROBYT_CNT ; 全バイト読んだ
  STA (ADDR_INDEX_L)   ; Zero Page Indirect
  INC ADDR_INDEX_L
  BNE LOAD_SKIPINC
  INC ADDR_INDEX_H
LOAD_SKIPINC:
  JMP LOAD_STORE_DATA

; --- ゼロバイトを数える ---
LOAD_ZEROBYT_CNT:
  ;JSR PRT_LF    ; ここがレコード端のはずだから改行すると見やすい
  LDA #'#'    ; ここがレコード端のはずだからメッセージ
  JSR PRT_CHAR_UART
  INC LOAD_CKSM
  BEQ LOAD_CHECKTYPE  ; チェックサムが256超えたらOK
  BRK
  ;JMP HATENA  ; おかしいのでハテナ出して終了

; --- 最終レコードを読み飛ばす ---
LOAD_SKIPLAST:
  JSR INPUT_CHAR_UART
  CMP #EOT
  BNE LOAD_SKIPLAST
  LDA #%10000000
  STA ECHO_F  ; エコーをもどす
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
  CMP #$0A              ; 改行だったらCTRLに戻る
  BEQ HATENA
  ;BEQ DEBUG_INPUT_BYT
  JSR NIB_DECODE
  ASL
  ASL
  ASL
  ASL
  STA ZR0
  JSR INPUT_CHAR_UART
  JSR NIB_DECODE
  ORA ZR0
  STA ZR0
  CLC
  ADC LOAD_CKSM ; Sレコードのチェックサム計算
  STA LOAD_CKSM
  LDA ZR0
  RTS

;DEBUG_INPUT_BYT:
;  LDA ZP_INPUT_BF_WR_P
;  JSR PRT_BYT
;  JSR PRT_S
;  LDA ZP_INPUT_BF_RD_P
;  JSR PRT_BYT
;  JSR PRT_S
;  LDA ZP_INPUT_BF_LEN
;  JSR PRT_BYT
;  JSR PRT_S
;  LDA #<INPUT_BF_BASE
;  STA ZP_GP0_VEC16
;  LDA #>INPUT_BF_BASE
;  STA ZP_GP0_VEC16+1
;  JSR DUMPPAGE
;  STZ ZP_INPUT_BF_WR_P
;  STZ ZP_INPUT_BF_RD_P
;  STZ ZP_INPUT_BF_LEN
;  BRK

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
  CMP #'0'
  BMI NIB_ERR
  CMP #'9'+1
  BPL NIB_HEX
  SEC
  SBC #'0'
  RTS
NIB_HEX:
  CMP #'A'
  BMI NIB_ERR
  CMP #'F'+1
  BPL NIB_ERR
  SEC
  SBC #'A'-$0A
  RTS
NIB_ERR:
  BRK

; *
; --- 文字列をUARTで出力する ---
; 先頭アドレスを指定する
; *
PRT_STR:
  STA ZR0
  STX ZR0+1
  LDY #$00
PRT_STR_LOOP:
  LDA (ZR0),Y   ;Zero Page Indirect Indexed with Y
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
  LDA #' '
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
  ;BIT ECHO_F
  ;BPL SKIP_ECHO         ; 設定に従う
  BBR7 ECHO_F,SKIP_ECHO ; CMOS命令！
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
PRT_CHAR_SHORTDELAY:
  STA UART::TX
  PHX
  LDX #$80
SHORTDELAY:
  NOP
  NOP
  DEX
  BNE SHORTDELAY
  PLX
  RTS

; print A reg to UART
PRT_CHAR_UART:
  STA UART::TX
DELAY_6551:
  PHY
  PHX
DELAY_LOOP:
  LDY #16
MINIDLY:
  LDX #$68
DELAY_1:
  DEX
  BNE DELAY_1
  DEY
  BNE MINIDLY
  PLX
  PLY
DELAY_DONE:
  RTS

;LCD_WAIT:
;  PHA             ; Push A
;  LDA #%00000000  ; Port B is input
;  STA VIA::DDRB
;LCDBUSY:
;  LDA #VIA::BPIN::LCD_RW
;  STA VIA::PORTA
;  LDA #(VIA::BPIN::LCD_RW | VIA::BPIN::LCD_E)
;  STA VIA::PORTA
;  LDA VIA::PORTB       ; Read data from LCD
;  AND #%10000000  ; if busy then %10000000 -> not zero -> zeroflag:0
;  BNE LCDBUSY     ; Branch if Not Equal(zeroflag=0)
;
;  LDA #VIA::BPIN::LCD_RW
;  STA VIA::PORTA
;  LDA #%11111111  ; Port B is output
;  STA VIA::DDRB
;  PLA             ; Pull A
;  RTS
;
;LCD_INST:
;  JSR LCD_WAIT
;  STA VIA::PORTB
;  LDA #0          ; Clear RS/RW/E bits
;  STA VIA::PORTA
;  LDA #VIA::BPIN::LCD_E          ; Enable up-down
;  STA VIA::PORTA
;  LDA #0          ; Clear (RS/RW)/E bits
;  STA VIA::PORTA
;  RTS
;
;PRT_CHAR_LCD:
;  JSR LCD_WAIT
;  STA VIA::PORTB
;  LDA #VIA::BPIN::LCD_RS         ; Only RegSelect HIGH
;  STA VIA::PORTA
;  LDA #(VIA::BPIN::LCD_RS | VIA::BPIN::LCD_E)   ; RegSelect and Enable HIGH
;  STA VIA::PORTA
;  LDA #VIA::BPIN::LCD_RS         ; Enable LOW
;  STA VIA::PORTA
;  RTS

; *
; --- UART割り込み処理 ---
; *
IRQ_UART:
  ; Aはすでにプッシュされている
  TXA
  PHA
; すなわち受信割り込み
  LDA UART::RX          ; UARTから読み取り
  LDX ZP_INPUT_BF_WR_P ; バッファの書き込み位置インデックス
  STA INPUT_BF_BASE,X ; バッファへ書き込み
  LDX ZP_INPUT_BF_LEN
  CPX #$BF             ; バッファが3/4超えたら停止を求める
  BCC SKIP_RTSOFF ; A < M BLT
; バッファがきついのでXoff送信
  LDA #XOFF
  JSR PRT_CHAR_SHORTDELAY
  ;STA UART::TX
SKIP_RTSOFF:
  CPX #$FF  ; バッファが完全に限界なら止める
  BNE SKIP_BRK
  BRK
SKIP_BRK:
; ポインタ増加
  INC ZP_INPUT_BF_WR_P
  INC ZP_INPUT_BF_LEN
EXIT_UART_IRQ:
  PLA
  TAX
  PLA
  CLI
  RTI

DUMPPAGE:
  ; モニタにあってもいいので追加したコマンド
  ; 指定アドレスから256バイトを吐き出す
  JSR BUILD_ADDR
  LDY #16
@LOOP:
  ; アドレス表示部
  JSR PRT_LF
  LDA ADDR_INDEX_H
  PHA
  JSR PRT_BYT
  LDA ADDR_INDEX_L
  PHA
  JSR PRT_BYT
  LDA #':'
  JSR PRT_CHAR_UART
  JSR PRT_S
  LDX #16
@BYTLOOP:
  ; データ表示部
  LDA (ADDR_INDEX_L)
  JSR PRT_BYT_S
  INC ADDR_INDEX_L
  BNE @SKP_H
  INC ADDR_INDEX_H
@SKP_H:
  DEX
  BNE @BYTLOOP
  LDX #16
  PLA
  STA ADDR_INDEX_L
  PLA
  STA ADDR_INDEX_H
  ; テキスト表示部
@ASCIILOOP:
  LDA (ADDR_INDEX_L)
  CMP #$20
  BCS @SKP_20   ; 20以上
  LDA #'.'
@SKP_20:
  CMP #$7F
  BCC @SKP_7F   ; 7F未満
  LDA #'.'
@SKP_7F:
  JSR PRT_CHAR_UART
  INC ADDR_INDEX_L
  BNE @SKP_H2
  INC ADDR_INDEX_H
@SKP_H2:
  DEX
  BNE @ASCIILOOP
  DEY
  BEQ @END
  BRA @LOOP
@END:
  JMP CTRL

; *
; --- 割り込み処理 ---
; *
IRQ:
  SEI ; RTI前に必ず切ること
  JMP (IRQ_VEC16) ; ベクタに飛ぶ（デフォルトで設定されているが変更されうる）

IRQ_ROM:
; --- ROM独自の割り込みハンドラ ---
; --- 外部割込み判別 ---
  PHA ; まだXY使用禁止
; UART
  LDA UART::STATUS
  BIT #%00001000
  BEQ IRQ_DEBUG ; bit3の論理積がゼロ、つまりフルじゃない
  JMP IRQ_UART  ; ベクタに飛ぶ（デフォルトで設定されているが変更されうる）
; VIA
;CHECK_VIA_IRQ:
;  LDA VIA::IFR ; 割り込みフラグレジスタ読み取り
;  ROL ; キャリーにIRQが
;  ROL ; キャリーにTIMER1が
;  BCC IRQ_DEBUG ; TIMER1割り込みじゃないならとりあえず無視
;  JMP (T1_IRQ_VEC) ; 所定のベクトルにタイマー割り込み（アプリケーションですきにしてよい）

IRQ_DEBUG:
; --- モニタに落ちる ---
  PLA
NMI:
  ; 押しボタン
  SEI
  STA A_SAVE
  STX X_SAVE
  STY Y_SAVE
  LDX #12-1
@STOREZRLOOP:     ; ゼロページレジスタを退避
  LDA ZR0,X
  STA ZR0_SAVE,X
  DEX
  BPL @STOREZRLOOP
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
  LDA #<STR_NEWLINE
  LDX #>STR_NEWLINE
  JSR PRT_STR

; A
  JSR PRT_S
  LDA #'a'
  JSR PRT_CHAR_UART

  LDA A_SAVE ; Acc reg
  JSR PRT_BYT

; X
  JSR PRT_S
  LDA #'x'
  JSR PRT_CHAR_UART

  LDA X_SAVE  ; X reg
  JSR PRT_BYT

; Y
  JSR PRT_S
  LDA #'y'
  JSR PRT_CHAR_UART

  LDA Y_SAVE  ; Y reg
  JSR PRT_BYT

; Flag
  JSR PRT_S
  LDA #'f'
  JSR PRT_CHAR_UART

  LDX SP_SAVE ; Flags
  INX ; SP+1=F
  LDA $0100,X
  JSR PRT_BYT

; PC
  JSR PRT_S
  LDA #'p'
  JSR PRT_CHAR_UART

  INX         ; SP+3=PCH
  INX
  LDA $0100,X
  JSR PRT_BYT

  DEX         ; PCL
  LDA $0100,X
  JSR PRT_BYT

  JSR PRT_S
  LDA #'s'
  JSR PRT_CHAR_UART

; SP
  LDA SP_SAVE     ; stack pointer
  JSR PRT_BYT
  CLI
  JMP CTRL

STR_NEWLINE: .BYT $A,"*",$00
STR_MESSAGE: .BYT "SD-Monitor  V.04","                        ","      for FxT-65",$00

