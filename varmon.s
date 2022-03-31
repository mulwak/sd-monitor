; --- アドレス定義 ---
.IMPORT __APP_RUN__

; アプリケーションRAM領域（ゼロページ）
.ZEROPAGE
  ZR0:               .RES 2  ; Apple][のA1Lをまねた汎用レジスタ
  ZR1:               .RES 2
  ZR2:               .RES 2
  ZR3:               .RES 2
  ZR4:               .RES 2
  ADDR_INDEX_L:      .RES 1  ; 各所で使うので専用
  ADDR_INDEX_H:      .RES 1
  ZP_INPUT_BF_WR_P:  .RES 1
  ZP_INPUT_BF_RD_P:  .RES 1
  ZP_INPUT_BF_LEN:   .RES 1
  ECHO_F:            .RES 1  ; エコーフラグ

; UART受信用リングバッファ
.SEGMENT "BF100"
INPUT_BF_BASE:  .RES 256

; モニタRAM領域
.SEGMENT "MONVAR"
  SP_SAVE:      .RES 1  ; BRK時の各レジスタのセーブ領域。
  A_SAVE:       .RES 1
  X_SAVE:       .RES 1
  Y_SAVE:       .RES 1
  ZR0_SAVE:     .RES 2
  ZR1_SAVE:     .RES 2
  ZR2_SAVE:     .RES 2
  ZR3_SAVE:     .RES 2
  ZR4_SAVE:     .RES 2
  LOAD_CKSM:    .RES 1
  LOAD_BYTCNT:  .RES 1
  T1_IRQ_VEC:   .RES 2  ; 2byte アプリケーションが用意するタイマ割り込み処理のベクタ
  UART_IRQ_VEC: .RES 2  ; 2byte アプリケーションによってとび先を変えられる、UART割り込み処理のベクタ

; アプリケーションRAM領域
APP_RAMBASE = __APP_RUN__

