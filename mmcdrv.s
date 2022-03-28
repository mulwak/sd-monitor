;DEBUGBUILD:
; https://github.com/gfoot/sdcard6502/blob/master/src/1_readwritebyte.s
.PROC MON
  .INCLUDE "sd-monitor.s"
.ENDPROC
.INCLUDE "FXT65.inc"

; 命名規則
; BYT  8bit
; SHORT 16bit
; LONG  32bit

; --- マクロ定義 ---

; loadmem16 T1_IRQ_VEC16,T1_IRQ
; メモリに16bit定数をロードする
.macro loadmem16 mem,cons
  LDA #<(cons)
  STA mem
  LDA #>(cons)
  STA mem+1
.endmac

.macro loadmem8l mem,cons
  LDA #<(cons)
  STA mem
.endmac

; regload16 T1_IRQ_VEC
; Aに低位、Xに上位をロードする
.macro loadreg16 cons
  LDA #<(cons)
  LDX #>(cons)
.endmac

.macro print  str_p
  loadreg16 str_p
  JSR MON::PRT_STR
.endmac

; --- アドレス
.ZEROPAGE
  ZP_GP0_VEC16:         .RES 2
  ZP_SDCMDPRM_VEC16:    .RES 2      ; コマンド引数4バイトを指す。アドレスであることが多いか。
  ZP_SDSEEK_VEC16:      .RES 2      ; カードレベルのポインタ
  ZP_LSRC0_VEC16:       .RES 2      ; ソースとディスティネーション。32bit演算用
  ZP_LDST0_VEC16:       .RES 2
  ZP_GP1_VEC16:         .RES 2
  ZP_SWORK0_VEC16:      .RES 2


; --- 変数領域定義
.SEGMENT "MONVAR"
SDCMD_CRC:          .RES 1
SECVEC32:           .RES 4  ; 4バイト セクタアドレス指定汎用
BOOT_LOAD_POINT:    .RES 2
BOOT_ENTRY_POINT:   .RES 2
.PROC DRV
  ; 各ドライブ用変数
  BPB_SECPERCLUS:   .RES 1  ; いらないのにデフォルト値が必須
  PT_LBAOFS:        .RES 4  ; セクタ番号
  FATSTART:         .RES 4  ; セクタ番号
  DATSTART:         .RES 4  ; セクタ番号
  BPB_ROOTCLUS:     .RES 4  ; クラスタ番号
  SEC_RESWORD:      .RES 1  ; 残りワード数  0ならCMD17データパケット途中ではない
.ENDPROC
.PROC DIR
  ; カレントディレクトリとその中のエントリ弄り用
  ; ファイルとしての実態こそがだいじ
  CUR_DIR:          .RES 4  ; クラスタ番号
  ENT_NUM:          .RES 1  ; 検索など何らかで選択されたエントリ番号（返り値用
  ENT_ATTR:         .RES 1  ; エントリの属性
  ENT_HEAD:         .RES 4  ; エントリの最初のクラスタ番号
  ENT_NAME:         .RES 2  ; ポインタ
  ENT_SIZ:          .RES 4  ; ファイルサイズバイト
.ENDPROC
.PROC FILE
  ; ファイルを開くとき必要な情報
  HEAD_CLUS:        .RES 4  ; クラスタ番号
  CUR_CLUS:         .RES 4  ; クラスタ番号
  CUR_SEC:          .RES 1  ; クラスタ内セクタ番号
  SIZ:              .RES 4  ; バイト数
  REAL_SEC:         .RES 4  ; セクタ番号
  RES_SIZ:          .RES 4  ; バイト数
  ENDSEC_FLG:       .RES 1  ; 残るサイズが1セクタ未満になると立つフラグ
.ENDPROC
RAW_SFN:            .RES 11 ; 11文字
DOT_SFN:            .RES 13 ; .とEOTを含んで13文字

; プログラム例
  ; LDA A_+DRV::OFS_PT_LBAOFS ; 変数領域を指すラベルに、構造体内部オフセットを加算してアクセス
  ;
  ; LDY OFS_PT_LBAOFS
  ; LDA (DRVSEL),Y           ; ドライブセレクタ変数に応じたアクセス
                             ; 4バイト変数へのアクセスが面倒だが仕方あるまい
  ; 普通に面倒なので別ドライブを扱うときはZ_にコピーすること
.SEGMENT "ALIGN100VAR"
SECBF512: .RES 512

; --- 定数
LCD_E   = VIA::BPIN::LCD_E
LCD_RW  = VIA::BPIN::LCD_RW
LCD_RS  = VIA::BPIN::LCD_RS
SD_CS   = VIA::BPIN::SD_CS
SD_SCK  = VIA::BPIN::SD_SCK
SD_MOSI = VIA::BPIN::SD_MOSI
SD_MISO = VIA::BPIN::SD_MISO

PORTA_OUTPUTPINS = LCD_E|LCD_RW|LCD_RS|SD_CS|SD_SCK|SD_MOSI

SD_STBITS = %01000000
SDCMD0_CRC = $95
SDCMD8_CRC = $87

; MBRオフセット
OFS_MBR_PARTBL = 446
; 区画テーブルオフセット
OFS_PT_SYSTEMID = 4
OFS_PT_LBAOFS = 8
; BIOSパラメータブロックオフセット
OFS_BPB_SECPERCLUS = 13 ; 1
OFS_BPB_RSVDSECCNT = 14 ; 2
OFS_BPB_FATSZ32 = 36    ; 4
OFS_BPB_ROOTCLUS = 44   ; 4
; ディレクトリエントリオフセット
OFS_DIR_ATTR = 11       ; 1
OFS_DIR_FSTCLUSHI = 20  ; 2
OFS_DIR_FSTCLUSLO = 26  ; 2
OFS_DIR_FILESIZE = 28   ; 4
; システム標識
SYSTEMID_FAT32 = $0B
SYSTEMID_FAT32NOCHS = $0C
; ディレクトリエントリアトリビュート
DIRATTR_DIRECTORY = $10
DIRATTR_LONGNAME = $0F

ZR0 = MON::ZR0
ZR1 = MON::ZR1

.SEGMENT "IPL"
IPL_RESET:
  LDA #PORTA_OUTPUTPINS
  STA VIA::DDRA
  print STR_START
  JSR SD_INIT
  JSR DRV_INIT

BOOT:
  ; ルートディレクトリを開く
  loadreg16 DRV::BPB_ROOTCLUS
  JSR FILE_OPEN
  ; BOOT.INIを探す
  print STR_SCFILE
  print STR_BOOTFILE
  loadreg16 STR_BOOTFILE
  JSR M_SFN_DOT2RAW_AXS
  JSR ETM_DIR_OPEN_BYNAME
  ; BOOT.INIを読む
  print STR_BTMOD
  JSR FILE_RDWORD           ; HEX1バイト:起動挙動 00=SDブート,01=モニタ
  JSR BLDPRTBYT             ; 文字列出力先の指定とかもできるかも？
  BEQ @SKPCTRL
  ; セクタを閉じる
  JSR FILE_THROWSEC
  JMP MON::CTRL
@SKPCTRL:
  JSR FILE_RDWORD           ; 改行と何か一つ読み飛ばす
  ; ブートローダ開始位置を決定する
  print STR_BTLOAD
  JSR FILE_RDWORD
  JSR BLDPRTBYT
  STA BOOT_LOAD_POINT+1
  JSR FILE_RDWORD
  JSR BLDPRTBYT
  STA BOOT_LOAD_POINT
  JSR FILE_RDWORD
  ; プログラムエントリポイントを決定する
  print STR_BTJUMP
  JSR FILE_RDWORD
  JSR BLDPRTBYT
  STA BOOT_ENTRY_POINT+1
  JSR FILE_RDWORD
  JSR BLDPRTBYT
  STA BOOT_ENTRY_POINT
  JSR FILE_RDWORD
  JSR MON::PRT_LF
  ; ブートローダバイナリのSFNを取得する
  loadmem16 ZP_SDSEEK_VEC16,DOT_SFN
  LDY #0
@SFNLOOP:
  PHY
  JSR FILE_RDWORD
  PLY
  STA (ZP_SDSEEK_VEC16),Y
  INY
  CPY #13
  BEQ @EXTL
  TXA
  STA (ZP_SDSEEK_VEC16),Y
  INY
  BRA @SFNLOOP
@EXTL:
  ; セクタを閉じる
  JSR FILE_THROWSEC
  ; ルートディレクトリを開く
  loadreg16 DRV::BPB_ROOTCLUS
  JSR FILE_OPEN
  ; ブートローダバイナリを探す
  print STR_SCFILE
  JSR M_SFN_DOT2RAW_WS
  JSR M_SFN_RAW2DOT_WS     ; ムダだが、きれいになる
  JSR MON::PRT_STR
  loadreg16 RAW_SFN
  JSR ETM_DIR_OPEN_BYNAME
  ; 配置
  LDA BOOT_LOAD_POINT
  LDX BOOT_LOAD_POINT+1
  JSR FILE_DLFULL
  ; 実行
  print STR_JUMPING
  JMP (BOOT_LOAD_POINT)

ETM_DIR_OPEN_BYNAME:
  ; 例外処理でモニタに落ちるシリーズ
  JSR DIR_OPEN_BYNAME
  CMP #$FF                  ; 見つからなかったらモニタへ
  BNE @SKP_HATENA
  JMP MON::HATENA
@SKP_HATENA:
  JSR OK

;  BRA .A
;
;  ; 任意クラスタ読み取り
;.LOOP
;  print STR_RS
;
;  JSR MON::INPUT_BYT
;  STA SECVEC32+3
;  JSR MON::INPUT_BYT
;  STA SECVEC32+2
;  JSR MON::INPUT_BYT
;  STA SECVEC32+1
;  JSR MON::INPUT_BYT
;  STA SECVEC32
;.B
;  JSR CLUS2SEC
;  loadmem16 ZP_SDCMDPRM_VEC16,SECVEC32
;  loadmem16 ZP_SDSEEK_VEC16,SECBF512
;  JSR SD_RDSEC
;.A
;  JSR .SHOWSEC
;  BRA .LOOP
;
;.SHOWSEC
;  loadmem16 ZP_GP0_VEC16,SECBF512
;  JSR DUMPPAGE
;  INC ZP_GP0_VEC16+1
;  JSR DUMPPAGE
;  RTS

DRV_INIT:
  ; MBRを読む
  loadmem16 ZP_SDCMDPRM_VEC16,BTS_CMDPRM_ZERO
  loadmem16 ZP_SDSEEK_VEC16,SECBF512
  JSR SD_RDSEC
  ;INC ZP_SDSEEK_VEC16+1    ; 後半にこそある。しかしこれも一般的サブルーチンによるべきか？
  LDY #(OFS_MBR_PARTBL-256+OFS_PT_SYSTEMID)
  LDA (ZP_SDSEEK_VEC16),Y ; システム標識
  CMP #SYSTEMID_FAT32
  BEQ @FAT32
  CMP #SYSTEMID_FAT32NOCHS
  BEQ @FAT32
  BRK
@FAT32:
  ; ソースを上位のみ設定
  LDA #(>SECBF512)+1
  STA ZP_LSRC0_VEC16+1
  ; DRV::PT_LBAOFS取得
  loadreg16 (DRV::PT_LBAOFS)
  JSR AX_DST
  LDA #(OFS_MBR_PARTBL-256+OFS_PT_LBAOFS)
  JSR L_LD_AS
  ; BPBを読む
  loadmem16 ZP_SDCMDPRM_VEC16,(DRV::PT_LBAOFS)
  DEC ZP_SDSEEK_VEC16+1
  JSR SD_RDSEC
  DEC ZP_SDSEEK_VEC16+1
  ; DRV::SEVPERCLUS取得
  LDY #(OFS_BPB_SECPERCLUS)
  LDA (ZP_SDSEEK_VEC16),Y       ; 1クラスタのセクタ数
  STA DRV::BPB_SECPERCLUS
  ; --- DRV::FATSTART作成
  ; PT_LBAOFSを下地としてロード
  loadreg16 (DRV::FATSTART)
  JSR AX_DST
  loadreg16 (DRV::PT_LBAOFS)
  JSR L_LD_AXS
  ; 予約領域の大きさのあと（NumFATsとルートディレクトリの大きさで、不要）をゼロにして、
  ; 予約領域の大きさを32bitの値にする
  LDA #0
  LDY #(OFS_BPB_RSVDSECCNT+2)
  STA (ZP_SDSEEK_VEC16),Y
  INY
  STA (ZP_SDSEEK_VEC16),Y
  ; 予約領域を加算
  loadreg16 (SECBF512+OFS_BPB_RSVDSECCNT)
  JSR L_ADD_AXS
  ; --- DRV::DATSTART作成
  ; FATの大きさをロード
  loadreg16 (DRV::DATSTART)
  JSR AX_DST
  loadreg16 (SECBF512+OFS_BPB_FATSZ32)
  JSR L_LD_AXS
  JSR L_X2                    ; 二倍にする
  ; FATSTARTを加算
  loadreg16 (DRV::FATSTART)
  JSR L_ADD_AXS
  ; --- ルートディレクトリクラスタ番号取得（どうせDAT先頭だけど…
  loadreg16 (DRV::BPB_ROOTCLUS)
  JSR AX_DST
  loadreg16 (SECBF512+OFS_BPB_ROOTCLUS)
  JSR L_LD_AXS
  RTS

SD_RDSEC:
  ; --- SDCMD_BF+1+2+3+4を引数としてCMD17を実行し、1セクタを読み取る
  ; --- 結果はZP_SDSEEK_VEC16の示す場所に保存される
  JSR SD_RDINIT
  JSR SD_DUMPSEC
  RTS

SD_RDINIT:
  ; CMD17
  LDA #17|SD_STBITS
  JSR SD_SENDCMD
  CMP #$00
  BEQ @RDSUCCESS
  CMP #$04          ; この例が多い
  JSR DELAY
  BEQ SD_RDINIT
  BRK
@RDSUCCESS:
  ;print STR_S
  JSR SD_WAITRES  ; データを待つ
  CMP #$FE
  BEQ @RDGOTDAT
  BRK
@RDGOTDAT:
  RTS

SD_DUMPSEC:
  ; 512バイト読み取り
  JSR RDPAGE
  INC ZP_SDSEEK_VEC16+1
  JSR RDPAGE
  ; コマンド終了
  LDA #SD_CS|SD_MOSI
  STA VIA::PORTA
  ;DEC ZP_SDSEEK_VEC16+1
  RTS

RDPAGE:
  LDY #0
@RDLOOP:
  PHY
  JSR SD_RDBYT
  PLY
  STA (ZP_SDSEEK_VEC16),Y
  INY
  BNE @RDLOOP
  RTS

SD_INIT:
  LDX #(80*2)
  JSR DUMMYCLK  ; 80回のダミークロック

@CMD0:
; GO_IDLE_STATE
; ソフトウェアリセットをかけ、アイドル状態にする。SPIモードに突入する。
; CRCが有効である必要がある
  loadmem16 ZP_SDCMDPRM_VEC16,BTS_CMDPRM_ZERO
  LDA #SDCMD0_CRC
  STA SDCMD_CRC
  LDA #0|SD_STBITS
  JSR SD_SENDCMD
  CMP #$01        ; レスが1であると期待（In Idle Stateビット）
  BNE @INITFAILED

@CMD8:
; SEND_IF_COND
; カードの動作電圧の確認
; CRCはまだ有効であるべき
; SDHC（SD Ver.2.00）以降追加されたコマンドらしい
  loadmem16 ZP_SDCMDPRM_VEC16,BTS_CMD8PRM
  LDA #SDCMD8_CRC
  STA SDCMD_CRC
  LDA #8|SD_STBITS
  JSR SD_SENDCMD
  CMP #$05
  BNE @SKP_OLDSD
  print STR_OLDSD ; Ver.1.0カード
  BRA @INITFAILED
@SKP_OLDSD:
  CMP #$01
  BNE @INITFAILED
  print STR_NEWSD ; Ver.2.0カード
  ; CMD8のR7レスを受け取る
  JSR SD_RDR7
@SKP_R7:

@CMD58:
; READ_OCR
; OCRレジスタを読み取る
  LDA #1        ; 以降CRCは触れなくてよい
  STA SDCMD_CRC
  loadmem16 ZP_SDCMDPRM_VEC16,BTS_CMDPRM_ZERO
  LDA #58|SD_STBITS
  JSR SD_SENDCMD
  JSR SD_RDR7

@CMD55:
; APP_CMD
; アプリケーション特化コマンド
; ACMDコマンドのプレフィクス
  loadmem16 ZP_SDCMDPRM_VEC16,BTS_CMDPRM_ZERO
  LDA #55|SD_STBITS
  JSR SD_SENDCMD
  CMP #$01
  BNE @INITFAILED

@CMD41:
; APP_SEND_OP_COND
; SDカードの初期化を実行する
; 引数がSDのバージョンにより異なる
  loadmem16 ZP_SDCMDPRM_VEC16,BTS_CMD41PRM
  LDA #41|SD_STBITS
  JSR SD_SENDCMD
  CMP #$00
  BEQ @INITIALIZED
  CMP #$01          ; レスが0なら初期化完了、1秒ぐらいかかるかも
  BNE @INITFAILED

  JSR DELAY         ; 再挑戦
  JMP @CMD55

@INITFAILED:  ; 初期化失敗
  print STR_SDINIT
  JMP MON::HATENA
  ; モニタに離脱
  ;JMP MON::CTRL

@INITIALIZED:
  print STR_SDINIT
OK:
  LDA #'!'
  JSR MON::PRT_CHAR_UART
  JSR MON::PRT_LF
  RTS
  RTS



MESSAGES:
.IFDEF DEBUGBUILD
  STR_CMD:     .BYTE $A,"CMD$",$0
.ENDIF
STR_START:   .BYTE $A,"IPL V.00",$A,$0
STR_SDINIT:  .BYTE "SD:Init...",$0   ; この後に!?
STR_OLDSD:   .BYTE "SD:Old",$A,$0
STR_NEWSD:   .BYTE "SD:>HC",$A,$0
STR_SCFILE:  .BYTE "SearchFile:",$0  ; この後に!?
STR_BTMOD:   .BYTE "Mode:",$0
STR_BTLOAD:  .BYTE $A,"Load:",$0
STR_BTJUMP:  .BYTE $A,"Jump:",$0
STR_JUMPING: .BYTE $A,"Jumping...",$A,$0
;STR_RS:
;  .ASCIIZ $A,"Read sector addr : $"
;STR_S:
;  .ASCIIZ "."
STR_BOOTFILE:
  .BYT "BOOT.INI"

; SDコマンド用固定引数
; 共通部分を重ねて圧縮している
BTS_CMD8PRM:   ; 00 00 01 AA
  .BYTE $AA,$01
BTS_CMDPRM_ZERO:  ; 00 00 00 00
  .BYTE $00
BTS_CMD41PRM:  ; 40 00 00 00
  .BYTE $00,$00,$00,$40

SD_RDBYT:
  ; --- カードを有効化して、MOSIハイの状態で8クロック
  ; --- MISOを得て返す
  LDX #8  ; シリアル8bit
@LOOP:
  ; クロック下げ↓
  LDA #SD_MOSI
  STA VIA::PORTA
  ; クロック上げ↑
  LDA #SD_MOSI|SD_SCK
  STA VIA::PORTA
  ; データ受信
  LDA VIA::PORTA
  AND #SD_MISO
  ; MISO入力をキャリーに反映する
  CLC
  BEQ @BITNOTSET
  SEC
@BITNOTSET:
  ; Yレジスタに結果を更新
  TYA
  ROL
  TAY
  DEX
  BNE @LOOP
  RTS

SD_WRBYT:
  ; MOSIからデータを送るために8クロック
  ; 受信は無視する
  LDX #8
@LOOP:
  ; 次のビットをキャリーに格納する
  ASL
  TAY
  LDA #0
  BCC @SENDBIT
  ORA #SD_MOSI
@SENDBIT:
  STA VIA::PORTA
  EOR #SD_SCK
  STA VIA::PORTA
  TYA
  DEX
  BNE @LOOP
  RTS

SD_WAITRES:
  ; --- SDカードが$FF以外の何かを返すのを待つ
  JSR SD_RDBYT
  CMP #$FF
  BEQ SD_WAITRES
  RTS

SD_SENDCMD:
  ; ZP_SDCMD_VEC16の示すところに配置されたコマンド列を送信する
  ; Aのコマンド、ZP_SDCMDPRM_VEC16のパラメータ、SDCMD_CRCをコマンド列として送信する。
  PHA

.IFDEF DEBUGBUILD
  ; コマンド内容表示
  print STR_CMD
  PLA
  PHA
  AND #%00111111
  JSR PRT_BYT_S
.ENDIF

  ; コマンド開始
  LDA #SD_MOSI ; CSロー
  STA VIA::PORTA
  ; コマンド送信
  PLA
  JSR SD_WRBYT
  ; 引数送信
  LDY #3
@LOOP:
  LDA (ZP_SDCMDPRM_VEC16),Y

  PHY
  ; 引数表示
  PHA
  JSR SD_WRBYT
  PLA
.IFDEF DEBUGBUILD
  JSR PRT_BYT_S
.ENDIF
  PLY

  DEY
  BPL @LOOP
  ; CRC送信
  LDA SDCMD_CRC
  JSR SD_WRBYT

.IFDEF DEBUGBUILD
  ; レス表示
  LDA #'='
  JSR MON::PRT_CHAR_UART
.ENDIF

  JSR SD_WAITRES
  PHA

.IFDEF DEBUGBUILD
  JSR PRT_BYT_S
.ENDIF

  LDA #SD_CS|SD_MOSI ; CSハイ
  STA VIA::PORTA
  LDX #(8*2)
  JSR DUMMYCLK  ; ダミークロック1バイト
  PLA
  RTS

SD_RDR7:
  JSR SD_RDBYT
  ;JSR PRT_BYT_S
  JSR SD_RDBYT
  ;JSR PRT_BYT_S
  JSR SD_RDBYT
  ;JSR PRT_BYT_S
  JSR SD_RDBYT
  ;JSR MON::PRT_BYT
  RTS

PRT_BYT_S:
  JSR MON::PRT_BYT
  JSR MON::PRT_S
  RTS

DUMPPAGE:
  ; モニタにあってもいいコマンド
  ; 範囲指定を追加するかが悩みどころ
@LOOP:
  JSR MON::PRT_LF
  LDA ZP_GP0_VEC16+1
  JSR MON::PRT_BYT
  LDA ZP_GP0_VEC16
  JSR MON::PRT_BYT
  LDA #':'
  JSR MON::PRT_CHAR_UART
  LDX #16
@LOOP2:
  LDA (ZP_GP0_VEC16)
  JSR PRT_BYT_S
  INC ZP_GP0_VEC16
  DEX
  BNE @LOOP2
  LDA ZP_GP0_VEC16
  BNE @LOOP
  RTS

DUMMYCLK:
  ; X/2回のダミークロックを送信する
  LDA #SD_CS|SD_MOSI
@LOOP:
  EOR #SD_SCK
  STA VIA::PORTA
  DEX
  BNE @LOOP
  RTS

EQBYTS:
  ; Yで与えられた長さのバイト列が等しいかを返す
  ; GP0とAX
  ; 文字列比較ではないのでNULLがあってもOK
  STA ZP_GP1_VEC16
  STX ZP_GP1_VEC16+1
@LOOP:
  DEY
  BMI @EQ               ; 初回で引っかかっても、長さ0の比較は問答無用で正しい
  LDA (ZP_GP0_VEC16),Y
  CMP (ZP_GP1_VEC16),Y
  BEQ @LOOP
@NOT:
  LDA #1
  RTS
@EQ:
  LDA #0
  RTS

DIR_OPEN_BYNAME:
  ; カレントディレクトリ内の名前に一致したファイルを開く
  ; AXで与えられた名前に合致するのを探す
  ; アトリビュートを返すので、ファイルかどうかはそっちで確認してね
  JSR DIR_GET_BYNAME
  CMP #$FF                ; 見つからなかったら$FFを返して終わり
  BEQ @EXT
@DIR_OPEN:
  loadreg16 DIR::ENT_HEAD
  JSR FILE_OPEN
  LDA DIR::ENT_ATTR
@EXT:
  RTS

DIR_GET_BYNAME:
  ; 名前に一致するエントリをゲットする
  ; Aには属性が入って帰る
  ; もう何もなければ$FFを返す
  ; 要求された文字列
  STA ZP_GP0_VEC16
  STX ZP_GP0_VEC16+1
  ; カレントディレクトリを開きなおす
  JSR FILE_REOPEN
  JSR DIR_RDSEC
  ; エントリ番号の初期化
  ;LDA #$FF
  ;STA DIR::ENT_NUM
  ;loadmem16 ZP_SDSEEK_VEC16,(SECBF512-32) ; シークポインタの初期化
  JSR DIR_NEXTENT_ENT
  BRA @LOOPENT
@LOOP:
  JSR DIR_NEXTENT
  CMP #$FF
  BNE @LOOPENT
  RTS
@LOOPENT:
  ;LDA ZP_SDSEEK_VEC16
  ;LDX ZP_SDSEEK_VEC16+1
  ;JSR PRT_DOTSFN
  LDA ZP_SDSEEK_VEC16
  LDX ZP_SDSEEK_VEC16+1
  LDY #11
  JSR EQBYTS
  BNE @LOOP
  LDA DIR::ENT_ATTR
  RTS

DIR_NEXTENT:
  ; 次の有効な（LFNでない）エントリを拾ってくる
  ; ZP_SDSEEK_VEC16が32bitにアライメントされ、DIR::ENT_NUMと一致するとする
  ; Aには属性が入って帰る
  ; もう何もなければ$FFを返す
  ; エントリ番号更新
@LOOP:
  LDA DIR::ENT_NUM
  INC
  STA DIR::ENT_NUM
  AND #%00001111
  BNE @SKP_NEXTSEC            ; セクタを読み切った
  JSR FILE_NEXTSEC            ; 次のセクタに進む
  JSR DIR_RDSEC               ; セクタを読み出す
  BRA @ENT
@SKP_NEXTSEC:
  ; シーク
  LDA ZP_SDSEEK_VEC16
  LDX ZP_SDSEEK_VEC16+1
  LDY #32
  JSR S_ADD_BYT
  STA ZP_SDSEEK_VEC16
  STX ZP_SDSEEK_VEC16+1
@ENT:
DIR_NEXTENT_ENT:
  JSR DIR_GETENT
  ;LDA (DIR::ENT_NAME)     ; 名前先頭
  LDA (ZP_SDSEEK_VEC16)
  BNE @SKP_NULL               ; 0ならもうない
  LDA #$FF
  RTS
@SKP_NULL:
  CMP #$E5                    ; 消去されたエントリ
  BEQ DIR_NEXTENT
  LDA DIR::ENT_ATTR
  CMP #DIRATTR_LONGNAME
  BNE @EXT
  BRA DIR_NEXTENT
@EXT:
  LDA DIR::ENT_ATTR
  RTS

DIR_GETENT:
  ; エントリを拾ってくる
  ; LFNだったらサボる
  ; 属性
  LDY #OFS_DIR_ATTR
  LDA (ZP_SDSEEK_VEC16),Y
  STA DIR::ENT_ATTR
  CMP #DIRATTR_LONGNAME
  BEQ @EXT
  ; 名前
  LDA ZP_SDSEEK_VEC16
  STA DIR::ENT_NAME
  LDA ZP_SDSEEK_VEC16+1
  STA DIR::ENT_NAME+1
  ; サイズ
  loadreg16 (DIR::ENT_SIZ)
  JSR AX_DST
  LDA ZP_SDSEEK_VEC16
  LDX ZP_SDSEEK_VEC16+1
  LDY #OFS_DIR_FILESIZE
  JSR S_ADD_BYT
  JSR L_LD_AXS
  ; クラスタ番号
  ; TODO 16bitコピーのサブルーチン化
  LDY #OFS_DIR_FSTCLUSLO
  LDA (ZP_SDSEEK_VEC16),Y      ; 低位
  STA DIR::ENT_HEAD
  INY
  LDA (ZP_SDSEEK_VEC16),Y      ; 低位
  STA DIR::ENT_HEAD+1
  LDY #OFS_DIR_FSTCLUSHI
  LDA (ZP_SDSEEK_VEC16),Y      ; 高位
  STA DIR::ENT_HEAD+2
  INY
  LDA (ZP_SDSEEK_VEC16),Y      ; 高位
  STA DIR::ENT_HEAD+3
@EXT:
  RTS

DIR_RDSEC:
  ; ディレクトリ操作用のバッファ位置は固定
  loadmem16 ZP_SDSEEK_VEC16,SECBF512
  loadmem16 ZP_SDCMDPRM_VEC16,(FILE::REAL_SEC)
  JSR SD_RDSEC
  DEC ZP_SDSEEK_VEC16+1
  RTS

FILE_OPEN:
  ; AXで与えられたクラスタ番号から、ファイル構造体を展開
  ; サイズに触れないため、ディレクトリにも使える
  ; --- ファイル構造体の展開
  ; 先頭クラスタ番号
  JSR AX_SRC
  loadreg16 FILE::HEAD_CLUS
  JSR AX_DST
  JSR L_LD
FILE_REOPEN:
  ; ここから呼ぶと現在のファイルを開きなおす
  STZ DRV::SEC_RESWORD
  ; 現在クラスタ番号に先頭クラスタ番号をコピー
  loadreg16 (FILE::CUR_CLUS)
  JSR AX_DST
  loadreg16 (FILE::HEAD_CLUS)
  JSR L_LD_AXS
  ; 現在クラスタ内セクタ番号をゼロに
  STZ FILE::CUR_SEC
  ; リアルセクタ番号を展開
  loadmem8l ZP_LDST0_VEC16,FILE::REAL_SEC
  JSR CLUS2SEC_IMP
  RTS

FILE_NEXTSEC:
  ; ファイル構造体を更新し、次のセクタを開く
  ; クラスタ内セクタ番号の更新
  LDA FILE::CUR_SEC
  CMP DRV::BPB_SECPERCLUS
  BNE @SKP_NEXTCLUS
  BRK                       ; TODO:FATを読む
@SKP_NEXTCLUS:
  INC FILE::CUR_SEC
  ; リアルセクタ番号を更新
  loadreg16 (FILE::REAL_SEC)
  JSR AX_DST
  LDA #1
  JSR L_ADD_BYT
  ; 残りバイト数を減算
  loadmem8l ZP_LDST0_VEC16,FILE::RES_SIZ+1
  LDA #1
  PHA
  JSR L_SB_BYT
  PLA
  JSR L_SB_BYT
CK_ENDSEC_FLG:
  ; 残るバイト数を評価
  ; ゼロ    0  （次のデータを要求してはいけない）
  ; 512以下 1
  ; 512以上 2
  LDA FILE::RES_SIZ+1
  AND #%11111110
  ORA FILE::RES_SIZ+2
  ORA FILE::RES_SIZ+3
  BNE @SKP_SETF
  ; 512以下である
  ORA FILE::RES_SIZ+1
  ORA FILE::RES_SIZ
  BEQ @ZERO   ; 完全なるゼロ
  LDA #$1
  BRA @SKP_RSTF
@SKP_SETF:
  ; 512以上である
  LDA #$2
@SKP_RSTF:
@ZERO:
  STA FILE::ENDSEC_FLG
  RTS


FILE_RDWORD:
  ; ファイルからデータを2バイト読み出してAXに
  ; TODO ファイル終端の検出
  LDA DRV::SEC_RESWORD
  BNE @SKP_RDCMD          ; CMD17が終わっているので新たにコマンドを送る
  loadmem16 ZP_SDCMDPRM_VEC16,FILE::REAL_SEC
  JSR SD_RDINIT
@SKP_RDCMD:
  JSR SD_RDBYT
  PHA
  JSR SD_RDBYT
  TAX
  PLA
  DEC DRV::SEC_RESWORD
  BNE @SKP_ENDSEC
  ; セクタが終わったので次のセクタを開く
  PHA
  PHX
  JSR FILE_NEXTSEC
  PLX
  PLA
@SKP_ENDSEC:
  RTS

FILE_THROWSEC:
  ; RDBYTを抜ける
  JSR SD_RDBYT
  JSR SD_RDBYT
  DEC DRV::SEC_RESWORD
  BNE FILE_THROWSEC
  ; コマンド終了
  LDA #SD_CS|SD_MOSI
  STA VIA::PORTA
  RTS

FILE_SETSIZ:
  ; DIR構造体に展開されたサイズをFILE構造体にコピー
  loadreg16 FILE::SIZ
  JSR AX_DST
  loadreg16 DIR::ENT_SIZ
  JSR L_LD_AXS
  loadreg16 FILE::RES_SIZ
  JSR AX_DST
  loadreg16 DIR::ENT_SIZ
  JSR L_LD_AXS
  JSR L_LD
  RTS

FILE_DLFULL:
  ; バイナリファイルをAXからだだっと展開する
  ; 速さが命
  STA ZP_SDSEEK_VEC16
  STX ZP_SDSEEK_VEC16+1
  ; サイズをロード
  JSR FILE_SETSIZ
@CK:
  JSR CK_ENDSEC_FLG
  CMP #1
  BEQ @ENDSEC           ; $1であれば最終セクタ
@LOOP:
  loadmem16 ZP_SDCMDPRM_VEC16,FILE::REAL_SEC
  JSR SD_RDSEC
  INC ZP_SDSEEK_VEC16+1
  JSR FILE_NEXTSEC
  CMP #2
  BEQ @LOOP              ; $2ならループ
@ENDSEC:
  CMP #0
  BEQ @END               ; $0なら終わり
  ; 最終セクタ
  LDA #$80
  STA DRV::SEC_RESWORD
  loadmem16 ZP_SDCMDPRM_VEC16,FILE::REAL_SEC
  JSR SD_RDINIT
  LDA FILE::RES_SIZ+1
  BIT #%00000001
  BEQ @SKP_PG
  ; ページ丸ごと
  STZ DRV::SEC_RESWORD
  JSR RDPAGE
  INC ZP_SDSEEK_VEC16+1
  ; 1ページ分減算
  loadmem8l ZP_LDST0_VEC16,FILE::RES_SIZ+1
  LDA #$1
  JSR L_SB_BYT
  ;BRA @CK
@SKP_PG:
  LDY #0
@RDLOOP:
  CPY FILE::RES_SIZ
  BEQ @SKP_PBYT
  PHY
  JSR SD_RDBYT
  PLY
  STA (ZP_SDSEEK_VEC16),Y
  INY
  BRA @RDLOOP
@SKP_PBYT:
  ; 残るセクタ分を処分
  STY ZR0
  LDA #0
  SEC
  SBC ZR0
  LSR
  ADC DRV::SEC_RESWORD
  STA DRV::SEC_RESWORD
  JSR FILE_THROWSEC
@END:
  RTS


;CLUS2SEC_AXD:
  ; 作業するDSTをAX指定
  ;JSR AX_DST
CLUS2SEC_AXS:
  JSR AX_SRC
CLUS2SEC_IMP:
  JSR L_LD
CLUS2SEC:
  ; クラスタ番号をセクタ番号に変換する
  ; SECPERCLUSは2の累乗であることが保証されている
  ; 2を減算
  LDA #$2
  JSR L_SB_BYT
  ; *SECPERCLUS
  LDA DRV::BPB_SECPERCLUS
@LOOP:
  TAX
  JSR L_X2
  TXA
  LSR
  ;BBR0 @LOOP ; なぜアセンブルできない
  CMP #1
  BNE @LOOP
  ; DATSTARTを加算
  loadreg16 (DRV::DATSTART)
  JSR L_ADD_AXS
  RTS

L_LD_AXS:
  STX ZP_LSRC0_VEC16+1
L_LD_AS:
  STA ZP_LSRC0_VEC16
L_LD:
  ; 値の輸入
  ; DSTは設定済み
  LDY #0
@LOOP:
  LDA (ZP_LSRC0_VEC16),Y
  STA (ZP_LDST0_VEC16),Y
  INY
  CPY #4
  BNE @LOOP
  RTS

AX_SRC:
  ; AXからソース作成
  STA ZP_LSRC0_VEC16
  STX ZP_LSRC0_VEC16+1
  RTS

AX_DST:
  ; AXからデスティネーション作成
  STA ZP_LDST0_VEC16
  STX ZP_LDST0_VEC16+1
  RTS

L_X2_AXD:
  JSR AX_DST
L_X2:
  ; 32bit値を二倍にシフト
  LDY #0
  CLC
  PHP
@LOOP:
  PLP
  LDA (ZP_LDST0_VEC16),Y
  ROL
  STA (ZP_LDST0_VEC16),Y
  INY
  PHP
  CPY #4
  BNE @LOOP
  PLP
  RTS

L_ADD_AXS:
  JSR AX_SRC
L_ADD:
  ; 32bit値同士を加算
  CLC
  LDY #0
  PHP
@LOOP:
  PLP
  LDA (ZP_LSRC0_VEC16),Y
  ADC (ZP_LDST0_VEC16),Y
  PHP
  STA (ZP_LDST0_VEC16),Y
  INY
  CPY #4
  BNE @LOOP
  PLP
  RTS

L_ADD_BYT:
  ; 32bit値に8bit値（アキュムレータ）を加算
  CLC
@C:
  PHP
  LDY #0
@LOOP:
  PLP
  ADC (ZP_LDST0_VEC16),Y
  PHP
  STA (ZP_LDST0_VEC16),Y
  LDA #0
  INY
  CPY #4
  BNE @LOOP
  PLP
  RTS

S_ADD_BYT:
  ; AXにYを加算
  STA ZP_SWORK0_VEC16
  STX ZP_SWORK0_VEC16+1
  TYA
  CLC
  ADC ZP_SWORK0_VEC16
  STA ZP_SWORK0_VEC16
  LDA #0
  ADC ZP_SWORK0_VEC16+1
  STA ZP_SWORK0_VEC16+1
  LDA ZP_SWORK0_VEC16
  LDX ZP_SWORK0_VEC16+1
  RTS

L_SB_BYT:
  ; 32bit値から8bit値（アキュムレータ）を減算
  SEC
@C:
  STA ZR0
  PHP
  LDY #0
@LOOP:
  PLP
  LDA (ZP_LDST0_VEC16),Y
  SBC ZR0
  PHP
  STA (ZP_LDST0_VEC16),Y
  STZ ZR0
  INY
  CPY #4
  BNE @LOOP
  PLP
  RTS

BLDBYT:
  ; 文字列AXをAにする
  JSR MON::NIB_DECODE
  ASL
  ASL
  ASL
  ASL
  STA ZR0
  TXA
  JSR MON::NIB_DECODE
  ORA ZR0
  RTS

BLDPRTBYT:
  JSR BLDBYT
  PHA
  JSR MON::PRT_BYT
  PLA
  RTS

M_SFN_DOT2RAW_WS:
  ; 専用ワークエリアを使う
  ; 文字列操作系はSRC固定のほうが多そう？
  loadreg16 DOT_SFN
M_SFN_DOT2RAW_AXS:
  JSR AX_SRC
  loadreg16 RAW_SFN
M_SFN_DOT2RAW_AXD:
  JSR AX_DST
M_SFN_DOT2RAW:
  ; ドット入り形式のSFNを生形式に変換する
  STZ ZR0   ; SRC
  STZ ZR0+1 ; DST
@NAMELOOP:
  ; 固定8ループ DST
  LDY ZR0
  LDA (ZP_LSRC0_VEC16),Y
  CMP #'.'
  BEQ @SPACE
  ; 次のソース
  INC ZR0
  BRA @STORE
  ; スペースをロード
@SPACE:
  LDA #' '
@STORE:
  LDY ZR0+1
  STA (ZP_LDST0_VEC16),Y
  INC ZR0+1
  CPY #7
  BNE @CKEXEND
@NAMEEND:
  ; 拡張子
  INC ZR0     ; ソースを一つ進める
@CKEXEND:
  CPY #12
  BNE @NAMELOOP
  ; 結果のポインタを返す
  LDA ZP_LDST0_VEC16
  LDX ZP_LDST0_VEC16+1
  RTS

M_SFN_RAW2DOT_WS:
  ; 専用ワークエリアを使う
  loadreg16 RAW_SFN
M_SFN_RAW2DOT_AXS:
  JSR AX_SRC
  loadreg16 DOT_SFN
M_SFN_RAW2DOT_AXD:
  JSR AX_DST
M_SFN_RAW2DOT:
  ; 生形式のSFNをドット入り形式に変換する
  LDY #0
@NAMELOOP:
  LDA (ZP_LSRC0_VEC16),Y
  CMP #' '
  BEQ @NAMEEND
  STA (ZP_LDST0_VEC16),Y
  INY
  CPY #8
  BNE @NAMELOOP
@NAMEEND:
  ; 最終文字がスペースかどうかで拡張子の有無を判別
  STY ZR0 ; DSTのインデックス
  LDY #8
  LDA (ZP_LSRC0_VEC16),Y
  STY ZR0+1 ;SRCのインデックス
  LDY ZR0
  CMP #' '
  BEQ @NOEX
  ; 拡張子あり
@EX:
  LDA #'.'
  STA (ZP_LDST0_VEC16),Y
  INY
  STY ZR0
@EXTLOOP:
  LDY ZR0+1
  LDA (ZP_LSRC0_VEC16),Y
  INY
  CPY #12
  BEQ @NOEX
  STY ZR0+1
  LDY ZR0
  STA (ZP_LDST0_VEC16),Y
  INY
  STY ZR0
  BRA @EXTLOOP
  ; 終端
@NOEX:
  LDY ZR0
  LDA #0
  STA (ZP_LDST0_VEC16),Y
  ; 結果のポインタを返す
  LDA ZP_LDST0_VEC16
  LDX ZP_LDST0_VEC16+1
  RTS

DELAY:
  LDX #0
  LDY #0
@LOOP:
  DEY
  BNE @LOOP
  DEX
  BNE @LOOP
  RTS

