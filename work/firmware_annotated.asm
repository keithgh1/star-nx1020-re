; ============================================================================
; NX1020 firmware (ROM2 v3.2) — annotated disassembly
; CPU: Mitsubishi M50734 (740 family). ROM mapped CPU 0x8000-0xFFFF (file -0x8000).
; See PORT_MAP.md for the port/bit definitions referenced below.
; RAM 0x0000-0x7FFF (SRAM IC5).  Font ROM via DME/MA bus.
; ============================================================================

; ---- RESET entry (vector 0xFFFE -> 0x8130) -------------------------------
RESET:                          ; 8130
        nop                     ; 8130  ea
        clc                     ; 8131  18   clear carry
        cld                     ; 8132  d8   clear decimal mode
        cli                     ; 8133  58   clear I (IRQ enabled; sources gated by ICON below)
        clt                     ; 8134  12   clear T flag (740: normal accumulator addressing)
        ldx #0xff               ; 8135  a2 ff
        txs                     ; 8137  9a   stack pointer = 0x01FF
        ldm #0xff,WDT           ; 8138  3c ff fc   kick watchdog (WDT=0xFC)

; ---- clear zero-page RAM 0x00..0xCF (variables; SFRs start at 0xDA) -------
        ldx #0x00               ; 813b  a2 00
        lda #0x00               ; 813d  a9 00
clear_zp:                       ; 813f
        sta mem_0000,x          ; 813f  95 00
        inx                     ; 8141  e8
        cpx #0xd0               ; 8142  e0 d0
        bne clear_zp            ; 8144  d0 f9

; ---- port initialization (see PORT_MAP.md) -------------------------------
        lda #0x20               ; 8146  a9 20
        sta P0FUNC              ; 8148  85 f5   P0.5=DME special fn (font-ROM bank enable); rest normal I/O
        lda #0xff               ; 814a  a9 ff
        sta P0                  ; 814c  85 f6   P0 output latch = all high
        lda #0x38               ; 814e  a9 38
        sta P0DIR               ; 8150  85 f7   P0.3(BUSYOUT)/P0.4(STBOUT)/P0.5(DME) = outputs
        lda #0x00               ; 8152  a9 00
        sta P1                  ; 8154  85 f3   P1 latch = 0  (P1 = host parallel data, latched input)
        lda #0x07               ; 8156  a9 07
        sta P1DIR               ; 8158  85 f4   P1.0-2 outputs, P1.3-7 inputs
        lda #0x04               ; 815a  a9 04
        sta P2P3FUNC            ; 815c  85 ed   Timer-S clk=f/16; P2=four-phase motor; P3.0/1 normal
        lda #0x90               ; 815e  a9 90
        sta P2                  ; 8160  85 f0   stepper phase init pattern (1001_0000)
        lda #0xff               ; 8162  a9 ff
        sta P2DIR               ; 8164  85 f1   P2 all outputs (carriage + line-feed motor phases)
        lda #0x00               ; 8166  a9 00
        sta P3                  ; 8168  85 ee   P3 = 0 (EEPROM SCLK/SIO low)
        lda #0x03               ; 816a  a9 03
        sta P3DIR               ; 816c  85 ef   P3.0(PWM)/P3.1(SCLK) outputs
        ldm #0x00,PHASECNT      ; 816e  3c 00 ec   reset motor phase counter

; ---- interrupt enable/mask (ICON1/2/3) -----------------------------------
        seb 2,ICON1             ; 8171  4f ff   enable IRQ source bit2 (Timer1/2/3 -> motor/print timing)
        clb 3,ICON1             ; 8173  7f ff   mask source 3
        clb 4,ICON1             ; 8175  9f ff   mask source 4
        clb 5,ICON1             ; 8177  bf ff   mask source 5
        clb 0,ICON2             ; 8179  1f fe   mask ICON2 sources 0..5
        clb 1,ICON2             ; 817b  3f fe
        clb 2,ICON2             ; 817d  5f fe
        clb 3,ICON2             ; 817f  7f fe
        clb 4,ICON2             ; 8181  9f fe
        clb 5,ICON2             ; 8183  bf fe
        seb 2,ICON3             ; 8185  4f fd   enable ICON3 source bit2
        seb 4,P0                ; 8187  8f f6   drive P0.4 (STBOUT) high
        seb 2,P2P3FUNC          ; 8189  4f ed   (re)assert Timer-S clock source select
        ldm #0xff,WDT           ; 818b  3c ff fc   kick watchdog
        jsr sub_7cf8            ; 818e  20 f8 7c   (watchdog/util routine)

; ---- RAM test: write/verify 0xAA then 0x55 via pointer (0x26/0x27) --------
        ldm #0xff,mem_0026      ; 8191  3c ff 26
        ldm #0x3f,mem_0027      ; 8194  3c 3f 27   ptr (0x26:0x27) = 0x3FFF
        ldy #0x00               ; 8197  a0 00
        lda #0xaa               ; 8199  a9 aa
        sta [mem_0026],y        ; 819b  91 26     [0x3FFF] = 0xAA
        lda #0x00               ; 819d  a9 00
        lda [mem_0026],y        ; 819f  b1 26     read back
        cmp #0xaa               ; 81a1  c9 aa
        beq ram_ok_aa           ; 81a3  f0 03
ram_fail:                       ; 81a5
        jmp err_7d6a            ; 81a5  4c 6a 7d   RAM error handler
ram_ok_aa:                      ; 81a8
        jsr sub_7cf5            ; 81a8  20 f5 7c
        lda #0x55               ; 81ab  a9 55
        sta [mem_0026],y        ; 81ad  91 26     [0x3FFF] = 0x55
        lda #0x00               ; 81af  a9 00
        lda [mem_0026],y        ; 81b1  b1 26
        cmp #0x55               ; 81b3  c9 55
        bne ram_fail            ; 81b5  d0 ee
        jsr sub_7cf8            ; 81b7  20 f8 7c

; ---- read/validate stored settings (EEPROM/EDS) with retry ---------------
        ldm #0x00,mem_00ae      ; 81ba  3c 00 ae
        ldm #0x40,mem_00af      ; 81bd  3c 40 af   ptr (0xAE:0xAF) = 0x4000
        jmp $+3                 ; 81c0  4c c3 81
        ldm #0x02,mem_0028      ; 81c3  3c 02 28   retry counter = 2
chk_sig:                        ; 81c6
        lda #0x3f               ; 81c6  a9 3f
        sta mem_0158            ; 81c8  8d 58 01
        jsr sub_771d            ; 81cb  20 1d 77   (read settings record)
        lda mem_0159            ; 81ce  ad 59 01
        cmp mem_807e            ; 81d1  cd 7e 80   compare vs ROM signature byte @0x807E
        bne sig_retry           ; 81d4  d0 08
        lda mem_015a            ; 81d6  ad 5a 01
        cmp mem_807f            ; 81d9  cd 7f 80   compare vs ROM signature byte @0x807F
        beq sig_ok              ; 81dc  f0 0c
sig_retry:                      ; 81de
        dec mem_0028            ; 81de  c6 28
        bne sig_try_again       ; 81e0  d0 03
        jmp err_7d71            ; 81e2  4c 71 7d   settings/signature error handler
sig_try_again:                  ; 81e5
        jsr sub_7841            ; 81e5  20 41 78
        bra chk_sig             ; 81e8  80 dc
sig_ok:                         ; 81ea
        jsr sub_7864            ; 81ea  20 64 78
        lda mem_0220            ; 81ed  ad 20 02
        sta mem_0053            ; 81f0  85 53     copy loaded settings -> working vars
        lda mem_0221            ; 81f2  ad 21 02
        sta mem_0054            ; 81f5  85 54
        ldm #0x00,mem_00c8      ; 81f7  3c 00 c8
        ldm #0x00,mem_00c9      ; 81fa  3c 00 c9
        bbc 7,mem_0053,$+...    ; 81fd  f7 53 0a  branch on settings bit7
        lda mem_0222            ; 8200  ad 22 02
        ; ... (continues: apply EDS settings, build init print params,
        ;      then falls through to the main loop at lab_8533)

; ============================================================================
; MAIN LOOP  (lab_8533) — fetch a received byte, apply char-table / 8th-bit
; rules, then dispatch control codes vs printable characters.
; Reached at startup and re-entered after each byte is handled.
; Key RAM vars (inferred from usage):
;   0x009f : status flags  (bit0 = special/pending state pending)
;   0x005b : input mode flags (bit1=force MSB, bit2=strip MSB, bit5=ESC-context)
;   0x0053 : EDS/settings copy (bit7 = char-set / IBM-vs-italic mode)
;   0x0056 : char-table mode flags     0x0062/0x0063 : emulation flags
;   0x0052 : print-attribute flags (proportional / NLQ / emphasized ...)
;   0x0100 : holds the current received character
; The byte source 0x64b7 is RAM-resident code (copied at init): it returns the
; next byte from the host-input ring buffer that the receive ISR (vec FFFA,
; RI/INT1) fills. Host parallel data is latched on P1; STB asserts the interrupt.
; ============================================================================
main_loop:                      ; 8533
        ldm #0xff,WDT           ; 8533  3c ff fc   kick watchdog each pass
        jsr get_rx_byte         ; 8536  20 b7 64   A = next received byte (RAM routine @64B7)
        bbc 0,mem_009f,no_pend  ; 8539  17 9f 03   if status.bit0 clear -> normal path
        jmp lab_ab48            ; 853c  4c 48 ab   else handle pending/special state
no_pend:                        ; 853f
        bbc 1,mem_005b,m_544    ; 853f  37 5b 02   mode.bit1: force MSB?
        ora #0x80               ; 8542  09 80        -> set bit7
m_544:                          ; 8544
        bbc 2,mem_005b,m_549    ; 8544  57 5b 02   mode.bit2: strip MSB?
        and #0x7f               ; 8547  29 7f        -> clear bit7
m_549:                          ; 8549
        sta mem_0100            ; 8549  8d 00 01   save working character
m_54c:                          ; 854c
        bbs 5,mem_005b,m_556    ; 854c  a7 5b 07   if in ESC-context, skip the '(' test
        cmp #0x28               ; 854f  c9 28      '(' ?
        bne m_556               ; 8551  d0 03
        jmp lab_bd8d            ; 8553  4c 8d bd     -> ESC '(' sequence handler
m_556:                          ; 8556
        bbs 4,mem_0062,m_563    ; 8556  87 62 0a
        cmp #0x7f               ; 8559  c9 7f      DEL (0x7F)?
        bne m_563               ; 855b  d0 06
        bbs 7,mem_0053,main_loop; 855d  e7 53 d3     IBM mode: ignore DEL -> loop
        jmp lab_a0ce            ; 8560  4c ce a0     else handle DEL (delete last)
m_563:                          ; 8563
        pha                     ; 8563  48         ---- clear a per-char flag byte ----
        ldx #0x1c               ; 8564  a2 1c
        lda #0x00               ; 8566  a9 00
        sta [mem_0000,x]        ; 8568  81 00      [ptr@0x1C] = 0
        pla                     ; 856a  68
        bbc 0,mem_00bc,m_581    ; 856b  17 bc 13   high-char remap enabled?
        cmp #0x80               ; 856e  c9 80
        bcc m_581               ; 8570  90 0f        only for codes >= 0x80
        and #0x7f               ; 8572  29 7f        fold 0x80-0xFF down to 0x00-0x7F
        pha                     ; 8574  48
        ldx #0x1c               ; 8575  a2 1c
        lda [mem_0000,x]        ; 8577  a1 00
        ora #0x08               ; 8579  09 08        mark "from high half" flag
        sta [mem_0000,x]        ; 857b  81 00
        pla                     ; 857d  68
        jmp printable           ; 857e  4c 71 86     -> treat as printable
m_581:                          ; 8581
        bbc 3,mem_0063,m_587    ; 8581  77 63 03
        jmp lab_861d            ; 8584  4c 1d 86
; --- classify: control code (<0x20) vs printable, honoring emulation flags ---
m_587:                          ; 8587
        ldm #0x00,mem_00b8      ; 8587  3c 00 b8
        bbc 2,mem_0056,m_590    ; 858a  57 56 03
        jmp lab_85d9            ; 858d  4c d9 85     (alternate char-table path)
m_590:                          ; 8590
        cmp #0xff               ; 8590  c9 ff
        bne m_596               ; 8592  d0 02
        lda #0x00               ; 8594  a9 00        0xFF -> 0x00
m_596:                          ; 8596
        cmp #0xa0               ; 8596  c9 a0
        bcc m_5a8               ; 8598  90 0e        < 0xA0 ?
        ...                     ;                   (>=0xA0: mark high, strip to 7-bit)
m_5a8:                          ; 85a8
        bbs 3,mem_00bc,m_5ad    ; 85a8  67 bc 02
        and #0x7f               ; 85ab  29 7f
m_5ad:                          ; 85ad
        cmp #0x20               ; 85ad  c9 20      space?
        bcc ctrl_code           ; 85af  90 0c        < 0x20 -> control code (lab_85bd)
        cmp #0x30               ; 85b1  c9 30
        bne printable           ; 85b3  d0 05
        bbc 0,mem_0056,printable; 85b5  17 56 02
        lda #0x00               ; 85b8  a9 00
        jmp printable           ; 85ba  4c 71 86
ctrl_code:                      ; 85bd  (dispatch C0 control via a jump table @ 0x60xx)
        bbs 7,mem_0053,m_5c8    ; 85bd  e7 53 08   pick table by char-set mode
        ldm #0x63,mem_0060      ; 85c0  3c 63 60     ptr = 0xC063 (std control-code table)
        ldm #0xc0,mem_0061      ; 85c3  3c c0 61
        bra m_5ce               ; 85c6  80 06
m_5c8:                          ; 85c8
        ldm #0x91,mem_0060      ; 85c8  3c 91 60     ptr = 0xC091 (IBM control-code table)
        ldm #0xc0,mem_0061      ; 85cb  3c c0 61
m_5ce:                          ; 85ce
        jsr sub_c2c0            ; 85ce  20 c0 c2   look up handler in table @[0x60]
        bcc back_to_loop        ; 85d1  90 03        not found -> ignore, loop
        clc                     ; 85d3  18
        jmp [mem_0060]          ; 85d4  b2 60        else jump to the control handler
back_to_loop:                   ; 85d6
        jmp main_loop           ; 85d6  4c 33 85

; ---- PRINTABLE CHARACTER -> render into the line buffer (lab_8671) ----------
printable:                      ; 8671
        bbc 7,mem_0052,p_868c   ; 8671  f7 52 18   attr.bit7 set?
        bbc 6,mem_0052,p_8682   ; 8674  d7 52 0b   attr.bit6 (style A)?
        bbc 5,mem_0052,p_868c   ; 8677  b7 52 12   attr.bit5 (style B)?
        pha
        jsr sub_d2c3            ; 867b  20 c3 d2     apply style transform A
        pla
        jmp p_868c              ; 867f  4c 8c 86
p_8682:                         ; 8682
        bbc 5,mem_0052,p_868c   ; 8682  b7 52 07
        pha
        clb 5,mem_006d          ; 8686  bf 6d
        jsr sub_c784            ; 8688  20 84 c7     apply style transform B
        pla
p_868c:                         ; 868c
        tst mem_0064            ; 868c  64 64      pending-column counter == 0 ?
        bne p_8699              ; 868e  d0 09
        bbc 5,mem_00bc,p_8696   ; 8690  b7 bc 03
        jmp lab_8787            ; 8693  4c 87 87
p_8696:
        jmp lab_86d3            ; 8696  4c d3 86
p_8699:                         ; 8699  store char + advance horizontal position
        pha
        jsr sub_8b4b            ; 869a  20 4b 8b     (compute glyph width / metrics)
        jsr sub_8c61            ; 869d  20 61 8c
        ldx #0x6e               ; 86a0
        ldy #0x70
        jsr sub_ff00            ; 86a4  22 00        16-bit helper (copy/add position)
        pla
        ldx #0x72
        ldy #0x6e
        jsr sub_ff0c            ; 86ab  22 0c        16-bit compare (position vs margin)
        bcs p_86b2              ; 86ad  b0 03
        jmp lab_88d8            ; 86af  4c d8 88     past right margin -> wrap/print line
p_86b2:                         ; 86b2  within margin: write char to buffer slot
        ldx #0x14
        sta [mem_0000,x]        ; 86b4  81 00        store char at column pointer (0x14)
        ; ... increments the 16-bit column pointer (set/clc/adc/clt = 740 16-bit add)
        ; then stores attribute nibble and jmp lab_887b (commit)
        jmp lab_887b            ; 86d0  4c 7b 88
; ============================================================================

; ============================================================================
; ESC & — DEFINE DOWNLOAD CHARACTERS   (cmd_esc_amp @ 0xB300)
; Protocol:  ESC '&' 0 n1 n2  then for each char n1..n2:  [attr][11 data cols]
; Storage (RAM): download font base = 0x0240, fixed slot per char:
;     draft = 13 bytes/char (sub_b845: 0x0240 + char*13)  -> [b0][b1=0][11 cols]
;     NLQ   = 32 bytes/char (sub_b877: 0x0240 + char*32)
;   b0 = transformed attribute (sub_b90b); columns masked so no two adjacent
;   columns share a row bit (col &= ~prev) — same invariant as the ROM fonts.
; Active only when EDS "RAM usage = Download" is selected (mem_0053 bit6).
; ============================================================================
cmd_esc_amp:                    ; b300
        bbc 6,mem_0053,not_dl   ; b300  d7 53 82   download RAM mode enabled? (EDS)
        jsr \sub_ff87           ; b303  22 87      read the "0" parameter
        cmp #0x00               ; b305  c9 00
        beq dl_ok               ; b307  f0 07        accept 0x00
        cmp #0x30               ; b309  c9 30        or '0'
        beq dl_ok               ; b30b  f0 03
        jmp main_loop           ; b30d  4c 33 85   else ignore command
dl_ok:                          ; b310
        bbc 2,mem_007b,dl_draft ; b310  57 7b 03   quality flag: draft vs NLQ
        jmp dl_nlq              ; b313  4c 92 b3     (NLQ path, 32-byte slots)
dl_draft:                       ; b316
        bbc 6,mem_00bc,dl_init  ; b316  d7 bc 03   first define? -> init RAM area
        jsr sub_ba0b            ; b319  20 0b ba     clear/seed download font RAM
dl_init:                        ; b31c
        clb 6,mem_00bc          ; b31c  df bc
        jsr \sub_ff87           ; b31e  22 87      n1 = first char code
        sta mem_008c            ; b320  85 8c
        jsr \sub_ff87           ; b322  22 87      n2 = last char code
        sta mem_008d            ; b324  85 8d
        cmp mem_008c            ; b326  c5 8c      ensure n1 <= n2 ...
        bcs dl_loop             ; b328  b0 06
        ldx mem_008c            ; b32a  a6 8c        ... else swap
        stx mem_008d            ; b32c  86 8d
        sta mem_008c            ; b32e  85 8c
dl_loop:                        ; b330  --- per character (code in mem_008c) ---
        lda mem_008c            ; b330  a5 8c
        cmp #0x20               ; b332  c9 20      space char?
        bne dl_glyph            ; b334  d0 23
        jsr sub_b845            ; b336  20 45 b8     dest = 0x0240 + char*13
        jsr \sub_ff87           ; b339  22 87        read attr byte
        jsr sub_b90b            ; b33b  20 0b b9     validate/transform attr
        ldy #0x00               ; b33e  a0 00
        sta [mem_0044],y        ; b340  91 44        b0 = attr
        iny                     ; b342  c8
        lda #0x00               ; b343  a9 00
        sta [mem_0044],y        ; b345  91 44        b1 = 0
        iny                     ; b347  c8
        ldm #0x0b,mem_0032      ; b348  3c 0b 32     11 columns
dl_sp:                          ; b34b
        jsr \sub_ff87           ; b34b  22 87        consume data byte
        lda #0x00               ; b34d  a9 00
        sta [mem_0044],y        ; b34f  91 44        store 0 (space = blank cols)
        iny                     ; b351  c8
        dec mem_0032            ; b352  c6 32
        bne dl_sp               ; b354  d0 f5
        jmp dl_next             ; b356  4c 83 b3
dl_glyph:                       ; b359  --- normal char ---
        jsr sub_b845            ; b359  20 45 b8     dest = 0x0240 + char*13
        jsr \sub_ff87           ; b35c  22 87        attr byte
        jsr sub_b90b            ; b35e  20 0b b9     validate/transform
        ldy #0x00               ; b361  a0 00
        sta [mem_0044],y        ; b363  91 44        b0 = attr
        iny                     ; b365  c8
        lda #0x00               ; b366  a9 00
        sta [mem_0044],y        ; b368  91 44        b1 = 0
        iny                     ; b36a  c8
        ldm #0x00,mem_008e      ; b36b  3c 00 8e     prev_col = 0
        ldm #0x0b,mem_0032      ; b36e  3c 0b 32     11 columns
dl_col:                         ; b371
        jsr \sub_ff87           ; b371  22 87        read column byte
        ora mem_008e            ; b373  05 8e        \  col &= ~prev_col
        eor mem_008e            ; b375  45 8e        /  (no adjacent dots)
        sta mem_008e            ; b377  85 8e        prev_col = col
        sta [mem_0044],y        ; b379  91 44        store column
        iny                     ; b37b  c8
        dec mem_0032            ; b37c  c6 32
        bne dl_col              ; b37e  d0 f1
        jmp dl_next             ; b380  4c 83 b3
dl_next:                        ; b383
        lda mem_008c            ; b383  a5 8c
        cmp mem_008d            ; b385  c5 8d      done last char?
        beq dl_done             ; b387  f0 06
        inc a                   ; b389  3a          next char code
        sta mem_008c            ; b38a  85 8c
        jmp dl_loop             ; b38c  4c 30 b3
dl_done:                        ; b38f
        jmp main_loop           ; b38f  4c 33 85
; dl_nlq @ b392: same but 32-byte slots (sub_b877); not_dl @ b285 skips/ignores.
; ============================================================================

; ============================================================================
; HARDWARE OUTPUT — GATE ARRAY + PRINT HEAD + STEPPER MOTORS
; ----------------------------------------------------------------------------
; The custom GATE ARRAY is memory-mapped at 0x4000-0x4003 in the *DME data
; space*. P0.5 = DME selects that space; every access is bracketed by
; `seb 5,P0FUNC`. Pointer mem_00ae:af = 0x4000 (set in init). The gate array is
; the hub between CPU, the 128 KB font ROM (MA0-16 bus) and the print head
; (HD0-9 / HDEN). Glyph columns are read from font ROM through it; head dot data
; and head/strobe timing are driven through it. STBT (Timer S, 0xFA) sets the
; head-strobe pulse width.
;
; Special-page I/O primitives (2-byte `jsr \subFF..`), all toggle DME (P0.5):
;   sub_ff4a  write gate-array reg0  ([0x4000])  <- head/data byte
;   sub_ff58  write reg1  ([0x4001]) (also cached in mem_00bb)
;   sub_ff51  write reg2  ([0x4002])
;   sub_ff61  write reg3  ([0x4003])
;   sub_ff33  read reg2   sub_ff3d read reg3   sub_ff3a return cached reg1
; (ff00/ff0c/ff18/ff22 are unrelated 16-bit add/sub/inc/dec helpers;
;  ff87 = get next host byte via RAM routine 0x64b7.)
sub_ff4a:                       ; ffXX  write gate-array reg0
        sty mem_010d            ; ff4a  save Y
        ldy #0x00               ; ff4d  reg index 0
        bra ga_write            ; ff4f
sub_ff61:                       ; write reg3
        sty mem_010d            ; ff61
        ldy #0x03               ; ff64
ga_write:                       ; ff66
        seb 5,P0FUNC            ; ff66  enable DME (select gate-array/data space)
        sta [mem_00ae],y        ; ff68  [0x4000 + reg] = A
        ldy mem_010d            ; ff6a  restore Y  (DME auto-context; P0.5 left set)
        rts                     ; ff6d
sub_ff3d:                       ; read gate-array reg3 (status)
        sty mem_010d            ; ff3d
        ldy #0x03               ; ff40
ga_read:                        ; ff42
        seb 5,P0FUNC            ; ff42  enable DME
        lda [mem_00ae],y        ; ff44  A = [0x4000 + reg]
        ldy mem_010d            ; ff46
        rts                     ; ff49

; ---- CARRIAGE PRINT-SWEEP (called once the line buffer is ready) -----------
; Polls the carriage ENCODER on P0.7 (both edges -> 2 dot-columns per box, the
; half-step pitch seen in the glyph data). On each edge sub_d94b runs a short
; settle delay; the gate array latches/fires the head column for that position.
; HCNT counts carriage columns; mem_0010 bit7 = "printing active" handshake.
print_sweep:                    ; d8d6 (entry context @ d8b6)
        ldm #0xff,WDT           ; d8d6  kick watchdog
        bbs 7,mem_0010,sw_go    ; d8d9  printing-active still set?
        jmp sweep_end           ; d8dc  no -> finish (lab_d954)
sw_go:                          ; d8df
        bbs 7,P0,print_sweep    ; d8df  wait for encoder edge (P0.7 low)
        jsr sub_d94b            ; d8e2  settle delay (head column latched here)
        bbs 7,P0,print_sweep    ; d8e5  confirm edge
        ; ... loop continues sampling the opposite edge (d8e8/d8fa) per column ...
        ; at line end -> step carriage:
carriage_step:                  ; d929
        seb 1,SMCONH            ; d929  carriage motor: assert step phase
        clb 1,mem_00bc          ; d92b
        clb 2,mem_005e          ; d92d
        jsr 0x483f              ; d92f  (RAM) motor phase/dwell
        clb 1,SMCONH            ; d932  release step phase
        jsr 0x481d              ; d934  (RAM) motor settle
        seb 6,mem_00b9          ; d937
        clb 1,SMCONH            ; d939
        ; ...
; NOTE: the *real-time* per-dot firing + motor micro-stepping are in the
; timer/HE-VE ISRs, which live in ROM1 mapped at CPU 0x4000-0x7FFF (NOT RAM):
;   isr_timer123 @4965  - dispatch by ICON2 bit -> per-timer handlers
;   isr_he_ve    @5046  - per-column carriage timing: reload HCNT, pulse SMCONH
;   isr_ri_int1  @5057  - host receive (fills ring buffer read by get_rx_byte)
;   isr_int2     @505F  - emergency stop: motors off (P2=0/SMCONH), head off, mask IRQs
; (CPU map: 0x0000-0x3FFF RAM, 0x4000-0x7FFF ROM1 system code, 0x8000-0xFFFF ROM2.)
; ============================================================================


