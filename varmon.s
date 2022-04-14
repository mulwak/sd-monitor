; モニタRAM領域
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

