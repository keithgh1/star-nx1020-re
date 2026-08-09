# Star NX-1020 - Theory of Operation

Reconstructed from reverse-engineering ROM1 (128 KB font/system) and ROM2 (32 KB firmware,
v3.2) plus the schematic. Confidence markers: ✅ established from code/schematic · 🔶 strong
inference · ❓ not yet traced (see "Open areas").

Built from the firmware and schematic first, then cross-checked against the NX-1020/LC-200
Technical Manual (Ch.2, Theory of Operation) - the manual confirmed the model on every major
mechanism; the few corrections it supplied are folded in and marked inline.

---

## 0. Hardware at a glance ✅
- **CPU**: Mitsubishi **M50734** (740-family, 6502-derived), 64-pin, external bus, no internal
  memory. Drives ports P0–P4, three timers, a UART, and a 4-phase stepper-motor controller.
- **ROM2 (IC6, 27256, 32 KB)** = firmware, mapped at CPU **0x8000–0xFFFF**.
- **RAM (IC5, 32 KB SRAM)** = CPU **0x0000–0x3FFF** (program space, DME off). Holds variables,
  line/print buffers, the host receive ring buffer, and the download-font area (0x0240).
  CPU **0x4000–0x7FFF** is **ROM1 system code** (the ISRs + core real-time routines live
  there, in ROM - not copied to RAM).
- **ROM1 (IC7, D27C1001, 128 KB)** = font + system data. It is **not** in CPU address space;
  it sits on a separate **MA0–MA16** bus behind the gate array and is read through the
  **DME** (Data Memory Enable) data window when P0.5=DME is asserted.
- **Gate array (NEC D65006)**: memory-mapped at **0x4000–0x4003 in the DME data space**. The
  I/O hub between CPU ⇄ font ROM ⇄ **print head** (HD0–9 / HDEN). Four registers (reg0–reg3).
- **Mechanism**: a 9-pin print head on a carriage driven by the **carriage stepper (SMCONH)**,
  paper advanced by the **line-feed stepper (SMCONV)**. Sensors: **home-position
  photo-interrupter on P0.7** (HIGH = at home; used only by the home-seek - there is no
  carriage encoder, sweeps are open-loop timer-paced), **paper-end reflective sensor on P0.6**
  (HIGH = paper present), **release / tractor leaf switches on P0.0 / P0.2** (the pair encodes
  friction / push-tractor / pull-tractor; both-HIGH is the manual's error state - PORT_MAP.md).
- **EEPROM (IC9, BR93C46)**: stores the EDS (Electronic DIP Switch) panel settings; serial
  interface bit-banged on **P1** (P1.0=CS, P1.1=SK, P1.2=DI, P1.4=DO).
- **Host interface**: Centronics parallel - data latched by the **gate array** at STROBE-fall,
  **BUSY/ACK/PE/SEL/ERR** out via LS05 buffers; /IN-PRIME (pin 31) → P0.1//INT2. (The CPU's
  UART TxD/RxD functions are unused; the serial option is an external converter box.)

---

## 1. Power-on / reset ✅ (RESET @ 0x8130)
1. **CPU housekeeping**: `clc/cld/cli/clt`, set stack to 0x01FF, kick watchdog (`WDT=0xFF`).
2. **Zero RAM variables** 0x00–0xCF.
3. **Port init** (exact values, see PORT_MAP.md):
   - `P0FUNC=0x20` → only P0.5 = DME special; `P0DIR=0x38` → P0.3 BUSY / P0.4 STB / P0.5 DME out.
   - `P1DIR=0x07` → P1.0–2 out (EEPROM CS/SK/DI), **P1.3–7 in** (P1.4 = EEPROM DO).
   - `P2P3FUNC=0x04`, `P2=0x90`, `P2DIR=0xFF` → P2 = 4-phase motor outputs, initial phase pattern.
   - `P3DIR=0x03` → P3.0/1 out (motor common voltage selects); P3.3-7 in (panel buttons);
     `PHASECNT=0`.
4. **Interrupt mask** via ICON1/2/3: enable only **/INT2 = host IN-PRIME** (ICON1 bit 2);
   all Timer1/2/3 interrupts masked (ICON2 cleared - the motion code enables them per move);
   Timer X count stopped (ICON3 bit 2).
5. **RAM test**: write/verify `0xAA` then `0x55` at 0x3FFF via an indirect pointer; branch to a
   RAM-error handler on mismatch.
6. **Load & validate settings**: read the stored settings record (EEPROM/EDS), compare a 2-byte
   **signature** against ROM bytes at 0x807E/0x807F, with a 2-try retry; on persistent failure →
   settings-error handler. On success, copy settings into working variables (0x0053/0x0054 …) and
   build the initial print parameters (pitch, quality, char table, line spacing, margins).
7. **Mechanical init** 🔶: home the carriage and clear the head. The audible **power-on "beep"**
   is produced by `beep_tone` (§7) pulsing the **print-head solenoids** at Timer1 frequency - there
   is no discrete buzzer. The carriage-home seek is `home_seek` @0xD840: if the HP flag (P0.7)
   is not already HIGH, start the carriage with a step budget, wait for the flag (double-read
   debounce), reverse/retry if the budget runs out, then edge-align.
8. Fall through to the **main loop** (0x8533).

### Interrupt architecture ✅
Vectors (ROM2 0xFFF4–0xFFFF) point mostly into the **0x49xx–0x50xx range = ROM1 system code
mapped at CPU 0x4000–0x7FFF**, not ROM2. HE/VE = the M50734's internal Horizontal/Vertical
stepper-counter-empty interrupts (SMCONH/SMCONV timing), not external signals:
| Vector | Target | Handler |
|--------|--------|---------|
| 0xFFF8 Timer1/2/3 | 0x4965 | `isr_timer123` - dispatches to motor micro-stepping sub-handlers |
| 0xFFF6 HE/VE      | 0x5046 | `isr_he_ve` - H/V counter empty: step SMCONH, reload HCNT |
| 0xFFFA RI/INT1    | 0x5057 | `isr_ri_int1` - **unused-source trap**: long beep → fatal-error path (host rx is polled via the gate array, not interrupt-driven) |
| 0xFFFC INT2       | 0x505F | `isr_int2` - **host /IN-PRIME reset**: head off, motors off, wait for line HIGH, re-init |
| 0xFFF4 TX/CNTR/BRK| 0x501A | UART/counter |
| 0xFFFE RESET      | 0x8130 | (in ROM2) |

(Note: the M50734 datasheet's vector table prints "INT1" for both priorities 2 and 3 - a
period typo. Fig.3's ICON1 bit names + firmware behavior fix the assignment as shown.)

---

## 2. Receiving data ✅ (corrected per manual p20)
- The host puts a byte on data lines 1–8 and pulses **STROBE** low (≥0.5 µs). The **gate array**
  latches the byte at STROBE-fall, drives **BUSY** (host must wait), and sets an internal **IA7**
  flag. The CPU sees IA7 via the data bus (DB7), reads the byte **from the gate array** (not from
  port P1 - our earlier P1 guess was wrong), and pushes it into a **ring buffer in RAM**; on
  completion it releases BUSY and pulses **ACK**.
- The foreground reads bytes with **`get_rx_byte` (RAM routine @0x64B7)**, which returns the next
  buffered byte to the main loop. This decouples host timing from print-engine timing (the printer
  can accept data while mechanically printing).
- 🔶 Serial input is an option via an external Serial-Parallel converter (DTR / XON-XOFF / ETX-ACK).

---

## 3. Main loop & command interpretation ✅ (main_loop @ 0x8533)
Per received byte:
1. Kick watchdog; fetch byte via `get_rx_byte`.
2. **8th-bit handling** per mode flags (0x005b): force MSB / strip MSB.
3. **DEL / high-char remap**: in IBM mode DEL is ignored; codes ≥0x80 may be folded to 0x00–0x7F
   with a "from high half" flag (selects the upper-128 glyph set).
4. **Classify**: `< 0x20` → **control code**; otherwise **printable**.
5. **Dispatch tables** (`sub_c2c0` walks 3-byte `[char, lo, hi]` entries, 0x00-terminated, then
   `jmp [handler]`). The active table is chosen by char-set mode (EDS bit7 @0x0053):
   - C0 control codes: STD @0xC063 / IBM @0xC091 (BEL, BS, HT, LF, VT, FF, CR, SO, SI, …, ESC).
   - **ESC** sequences: STD @0xC0D4 / IBM @0xC1D8 - the full ESC/P + IBM command set (~77 commands;
     see ESC_COMMANDS.md). A handler address of 0x8533 = "accepted but ignored in this emulation."
- Commands set **state** (pitch, quality draft/LQ, typeface via `ESC k`, italic, emphasized,
  proportional, line spacing, margins, tabs, char table, bit-image mode, download-font define, …).
  Style attributes are stored as flag bits (0x0052/0x0062/0x0063/0x005b/0x0056) consulted later.

---

## 4. Building a print line ✅ (printable @ 0x8671)
A printable character is **rendered into a RAM line buffer column-by-column**, not printed
immediately (the printer buffers a full line, then sweeps the head across it):
1. Apply any **programmatic style transforms** flagged for this char (emphasized, expanded, etc.).
2. Compute the glyph's **width/metrics** (`sub_8b4b`/`sub_8c61`).
3. **16-bit horizontal position** math: advance the column pointer by the glyph width and compare
   against the **right margin**. If it would overflow → wrap / flush the line (print it now).
4. Else **store the char + attribute** at the current column slot (column pointer @0x14) and advance.
- **Download characters** (`ESC &`, cmd_esc_amp @0xB300) define user glyphs into the RAM area at
  **0x0240** (draft = 13 bytes/char, NLQ = 32 bytes/char) when EDS "RAM usage = Download" is set.
  Stored with the same packing as ROM glyphs (attribute byte + columns; adjacent-column dot
  exclusion `col &= ~prev`).

---

## 5. Font / glyph lookup ✅ (resident fonts)
When the line is sent to the head, each character's bitmap is fetched from **ROM1 via the gate
array**:
- **Selection chain**: typeface (`ESC k`, or panel) + quality (draft/LQ) + style → a font **index**
  (Courier 0x14, Sanserif 0x1e, Orator 0x28, Script 0x32) → a **descriptor** → an **8-byte-per-char
  metrics table** (in ROM1 bank2, 0x10000–0x17FFF). Each entry = `[glyph_ptr(2B), +6 metric bytes]`;
  **width = ptr(c+1) − ptr(c)** (glyphs packed contiguously).
- **Bank/address**: the glyph pointer is a 15-bit offset in the 0x8000–0xFFFF DME window; the actual
  byte address is **contiguous across the 128 KB, file offset wrapping mod 0x20000** (bank3 0x18000–
  0x1FFFF → bank0 0x00000). Courier/Sanserif live in bank3; **Orator/Script in bank0**.
- **Glyph formats**:
  - **Draft (8-dot)**: column-major, 1 byte/col, bit7 = top pin.
  - **NLQ (16-dot)**: **planar interleaved** - `g[0:h]` → even rows, `g[h:2h]` → odd rows (two-pass
    half-dot vertical offset), h = width/2 columns, drawn at half horizontal pitch. Stored glyph =
    exactly **16 half-rows × ≤23 columns** (verified: all glyph widths are exactly 2×columns; max
    23 columns matches the manual's "23"). The manual's "18×23" cell = the physical head grid
    (9 pins × 2 passes); the resident faces use 8 pins/pass (16 rows), and the **9th pin** (bottom
    2 half-rows) comes from the separate HD9 write path (underline / 9th-pin), not per-glyph data.
- **Styles**: italic = programmatic slant; bold/emphasized/double-strike/condensed/expanded/
  super-sub = programmatic transforms applied during rendering - **not** separate stored glyphs.
  Script is the one inherently-cursive resident face.
- The gate array is told the font address; **DME (P0.5)** is asserted around each read; glyph
  column bytes are read back through the gate array. (All five resident typefaces have been
  extracted: see FONT_*.png.)

### 5a. Print modes & High-Speed Draft ✅ (fully traced)
Quality lives in `mem_007b` bit2 (clear = Draft, set = LQ/Courier); pitch in `mem_0062`
(pica bit0 / elite bit1 / condensed bit2). The four EDS print modes are decoded from
**`mem_0054` bits 6-7** (the EDS C-1/C-2 field) at init and on master-select - exactly matching
the manual's table:
| `mem_0054 & 0xC0` | mode set | manual |
|---|---|---|
| `0x40` | Draft + **HS** (`mem_00bc` bit4 enable + bit1 active) + pica | **10 CPI HS DRAFT** |
| `0x00` | Draft, HS off, pica | 10 CPI DRAFT |
| `0x80` | Draft, HS off, condensed | 17 CPI DRAFT |
| `0xC0` | LQ (`mem_007b` bit2/4), pica | 10 CPI COURIER |

**High-Speed Draft** = draft quality run at higher carriage speed:
- **`mem_00bc` bit4 = HS enable** (from EDS / master select). `sub_99ad` then sets
  **`mem_00bc` bit1 = HS active** *only* when: draft quality AND HS enabled AND **not condensed**
  AND not the bit5 special mode - so HS applies only at pica/elite draft (matching the spec).
- **Effect**: the HS-active flag selects **faster carriage-motor timing constants** in the motor
  stepping routines (e.g. `sub_4809` loads period `0x014C` HS vs `0x018C` normal; `sub_481d`
  `0x0088` vs `0x00C8` - shorter = faster), and `sub_9e0b` programs a different speed bit into the
  gate-array control reg (draft → control **bit4** HS vs **bit5** normal). It also adjusts glyph
  width/spacing (`sub_8b4b` reads the flag). Net: **200/225 cps** vs Draft's **150/180 cps**.
- It is the same draft glyph data, just printed with the carriage moving faster (wider effective
  dot spacing), which is why HS-Draft output is lighter/faster than normal Draft.

---

## 6. The gate array - the print I/O hub ✅
Memory-mapped 0x4000–0x4003 in DME space; every access bracketed by `seb 5,P0FUNC` (enable DME).
Special-page primitives:
| Primitive | Reg | Use |
|-----------|-----|-----|
| `sub_ff4a` | reg0 write | **print-head column data byte** (also font/data) |
| `sub_ff58` | reg1 write | control (cached in mem_00bb) |
| `sub_ff51` | reg2 write | **font-ROM bank select** (top 2 bits) + control |
| `sub_ff61` | reg3 write | control |
| `sub_ff33`/`sub_ff3d` | reg2/reg3 read | status |
- **STBT** (Timer S, 0xFA) sets the **head-strobe pulse width**; init writes `0xAA/0x55` to reg0 to
  test the head shift register.

---

## 7. Sending data to the print head ✅ (firing a column - fully traced)
**Line-print dispatcher** (0xE4F2+): a set of near-identical loops, one per pitch/quality/width
mode (selected by flags `mem_007b`/`007c`/`00b2`). Each iteration: `sub_e729` (next char from the
line buffer) → `sub_f3fb` (resolve glyph address/metrics) → a per-mode **column-emit routine**
(`sub_e804` draft, `sub_e831` double-width, `sub_e89e`/`e8b6` NLQ two-pass, `sub_e970`/`e9b1`/
`ea2c` other pitches) → `sub_ff9f` (advance / end-of-line test).

**Each emit routine** loops over the glyph's columns (count in `mem_010e`, glyph pointer in
`mem_0044`): read a column byte → `sub_f1d5` (format + fire). Double-width inserts a blank column
between each; NLQ emits the two half-dot passes.

**`sub_f1d5` = format one column** into the head's pin layout: a long `rol/ror a,mem_008b` sequence
spreads the 8 glyph bits across a 16-bit field per the active pitch (doubling bits for expanded
modes, applying the half-dot interleave), carrying an overlap bit between columns in `mem_0011`
bit7, and OR-ing in descender/9th-pin bits. Result → `mem_000d`.

**`sub_f394` = sync to carriage position + fire** (the heart of the print path):
1. **Wait for the column slot**: spin on **P0.4** (strobe window) and **`mem_0010` bit6** - the
   per-column "carriage advanced, fire now" flag that the **Timer1/2/3 ISR sets** (`seb 6,mem_0010`
   @0x49EC/0x4B87) each time it micro-steps the carriage one column.
2. **Shift the column into the head shift register** via successive writes to gate-array **reg0**
   (`[0x4000]`): first a `0x80`/`0x00` overlap/9th-pin byte (from `mem_0011` bit7), then the 8-pin
   pattern, then up to two `0x00` padding bytes for narrower modes - **1–4 bytes/column**.
3. **`sei`** → set **P0.4 = STBOUT** → load **STBT** (strobe width: **0xCE** normal, **0xF3** for
   the darker/high-quality mode per `mem_0053` bit3 / `mem_0057` bit1) → **drive P0.4 low** = fire
   the solenoids (Timer-S/STBT times the energizing pulse) → **`cli`**.
4. **`clb 6,mem_0010`** (consume the slot) and clear the overlap flag; check P3.7 (the
   /ON-LINE button - a mid-job pause check, not a paper sensor).
- **STBT therefore = dot energy/darkness**; four widths exist in firmware (0x26 used by `beep_tone`,
  0x78, 0xCE, 0xF3). This whole primitive is proven by `beep_tone` @0x6466, which reuses it (reg0
  ← 0x80/0xFF, STBT=0x26, paced by Timer1) to make the power-on tone - i.e. the "beep" is the head
  solenoids firing, no buzzer. The foreground formats+fires each column; the **timer ISR paces the
  carriage** and releases each column slot, so the two run in lock-step.

---

## 8. Moving the carriage (horizontal) ✅ (column pacing - refined)
- The carriage stepper is **SMCONH** (0xF8); its 4 phases come out on P2 (low nibble) via the
  M50734 stepper controller, advanced through `PHASECNT`.
- **Columns are paced by the Timer1/2/3 ISR**, not the HE/VE ISR (correction to earlier note): the
  timer ISR micro-steps the carriage at a constant rate and, at each dot-column position, sets
  `mem_0010` bit6 to **release the foreground** to fire that column (§7). It also reloads **HCNT**
  (column counter) and increments the column index. `mem_0010` bit7 = "printing active" gates the
  whole sweep.
- **There is no carriage encoder.** P0.7 is the **home-position photo-interrupter** (HIGH =
  shield at home), and its only reads are in the home-seek/edge-align code at 0xD840–0xD906
  (earlier read as "encoder polling in print_sweep" - that was this same code). Sweep motion
  is fully open-loop: timer-paced constant velocity from a known home reference.
- The **HE/VE ISR** (`isr_he_ve` @0x5046) is the M50734's **H/V stepper-counter-empty**
  interrupt (internal SMCONH/SMCONV event, per datasheet) - it steps SMCONH and reloads HCNT
  when the horizontal counter expires, complementing the Timer1/2/3 pacing.
- At end of line, `carriage_step` (@0xD929) pulses SMCONH to park/reverse; a RAM motor routine
  handles phase dwell/settle.
- 🔶 **Bidirectional printing**: an `ESC U` / unidirectional flag exists; logic-seeking and the
  column-order reversal for right-to-left passes are implied but ❓ not yet traced.

---

## 9. Feeding paper (vertical) ✅ (line-feed quantization - fully traced)
- The line-feed stepper is **SMCONV** (0xF9), 4 phases on P2 (high nibble), micro-stepped by the
  **Timer1/2/3 ISR sub-handlers** (0x4E69–0x5008): they advance the SMCONV phase, read the
  **paper-end sensor (P0.6)** and the **/ON-LINE button (P3.7)**, and decrement a 16-bit
  remaining-step counter `mem_0041/0042` (via `sub_4e5b`) to zero.
- **Unit = 1/432 inch, and 1 unit = exactly 1 motor micro-step → 432 steps/inch.** Proven by the
  line-spacing handlers, which store the per-line distance in `mem_003f/0040` in these units:
  | Command | meaning | units stored |
  |---------|---------|--------------|
  | `ESC 0` | 1/8" | 54 (=432/8) |
  | `ESC 2` | 1/6" | 72 (=432/6) |
  | `ESC 1` | 7/72" | 42 (=7×6) |
  | `ESC A` n | n/72" | n×6 (computed n×4 + n×2) |
  | `ESC 3` / `ESC J` n | **n/216"** | n×2 |
  (`ESC 3`/`J` confirm the base unit: n×2 = n/216" ⇒ 1 unit = 1/432". The 9-pin minimum feed is
  1/216" = 2 steps.)
- **Feed execution** (LF/CR @0x953E): the handler **coalesces consecutive CR/LF bytes**, counting
  them in `mem_0032/0033` (peeking ahead in the buffer), then computes **total = count × per-line
  spacing** by repeated 16-bit add into `mem_003d/003e`. `sub_d69d` copies that total into the motor
  counter `mem_0041/0042`, **adds a constant 0x48 = 72-step (1/6") ramp/overhead allowance**,
  asserts SMCONV, and the timer ISR steps the motor along an **acceleration/dwell profile** (the
  long ramp tables in **ROM1 0x05A42–0x06243**, indexed via `sub_d7e1`) until the count hits zero.
- **Page/form control**: `ESC C` page length, `ESC N/O` skip-perforation, VTAB channels (`ESC B`),
  paper-out detect (`ESC 8/9`), ASF/paper control (`ESC EM`) set state the feed path honors.
  🔶 The exact accel-ramp table contents remain to confirm. (Sensor identities are settled:
  P0.6 = paper-end sensor, P3.7 = On Line button - see PORT_MAP.md.)

---

## 10. Error / stop / protection paths ✅ (refined per manual p29-30)
- **`isr_int2`** (INT2) = **host INPUT-PRIME reset** (CN1 pin 31 → INIT2): writes 0x00 to head
  reg0 (head off), turns off both motors (P2=0, SMCONH/SMCONV cleared), masks the timer/motor IRQs,
  then re-initializes. (Not "cover-open" as earlier guessed - it's the host re-init line.)
- **Watchdog protection**: the CPU normally outputs LOW on **WD OUT** (`WDT` kicked everywhere); on
  a hang the voltage-detect IC asserts RESET to CPU + gate array, which **ignores all head/motor
  drive signals** - hardware runaway protection. Also resets if +5 V dips below 4.25 V.
- RAM-test and settings-signature failures at boot jump to dedicated error handlers (0x7D6A/0x7D71).

## 11. Print-head thermal protection ✅ (manual p25 - newly added)
A **thermistor in the head** feeds **P4.3/AN3** (TH+ = 5 V, NTC down to a 10k/cap divider
node; hotter = higher reading). The A/D read + thresholds are located: `head_thermal_check`
@0xD990 is the ROM's only A/D sequence (ADCON channel 3, start, poll, read ADR). Thresholds
on the 8-bit reading: **< 0xD1** normal (≤115 °C); **0xD1–0xD9** interval printing (~115–125 °C,
10 pause calls per check ≈ the manual's 0.5 s/line); **≥ 0xDA** stop-and-cool (~125 °C: head
masked via gate array, long waits, re-measure); **≥ 0xFC / < 0x04** = thermistor short/open →
fatal error trap. Matches manual p25.

---

## Open areas (status)
1. **Per-column head-fire sequencing** ✅ RESOLVED - see §7 (dispatcher → emit → `sub_f1d5` format →
   `sub_f394` sync+fire; column shifted into head reg0 as 1–4 bytes; STBT strobe; timer-ISR slot
   handshake). Remaining detail: exact NLQ two-pass interleave vs. alternate-sweep, and the precise
   HD0–9 wiring order (the shift-register bit order).
4. **Line-feed quantization** ✅ RESOLVED - see §9 (1/432" unit = 1 micro-step = 432 steps/inch;
   CR/LF coalescing × spacing; `sub_d69d` + 72-step ramp allowance). Remaining detail: the
   accel-ramp table contents in ROM1 0x05A42–0x06243.

3. **Carriage-home seek** ✅ RESOLVED - `home_seek` @0xD840 (see §1.7 / §8): P0.7 home flag,
   step budget, debounce, reverse/retry, edge-align. No encoder exists.
5. **Sensor map** ✅ RESOLVED (schematic trace, Aug 2026) - P0.0 release switch, P0.2 tractor
   switch, P0.6 paper-end sensor, P0.7 home interrupter, P3.3–3.7 panel buttons, P4.3
   thermistor. Full pin-level detail in PORT_MAP.md. (ASF command path still untraced.)
6. **HE vs VE distinction** ✅ RESOLVED - datasheet: HE/VE are the internal Horizontal
   (SMCONH/carriage) and Vertical (SMCONV/paper) stepper-counter-empty interrupts.

Still open (not yet traced):
2. **Bidirectional / logic-seeking** ❓ - direction decision, column reversal, dot-timing comp.

These are the spots to either trace further in the firmware or verify against the technical manual.
