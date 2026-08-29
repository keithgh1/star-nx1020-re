# NX1020 ROM memory map (drill-down)

Status legend: ✅ verified · 🔶 strong inference · ❓ needs drill-down

## Hardware context (from schematic)
- CPU **M50734** (740-family / 6502-like), external bus. ✅
- **IC6 27256 (32 KB)** = firmware, mapped to CPU **0x8000–0xFFFF**. = our `ROM2`. ✅
- CPU program space (DME off): **0x0000–0x3FFF = RAM** (IC5), **0x4000–0x7FFF = ROM1 system
  code** (ISRs + core routines), **0x8000–0xFFFF = ROM2** firmware. ✅ (corrected)
- **IC7 D27C1001 (128 KB) = `ROM1`** - dual-purpose: its `0x4000–0x7FFF` appears in CPU program
  space (above); the font/glyph data is read via the **DME data space** (P0.5) through the gate
  array (MA0–MA16 bus). ✅
- ✅ **The DME window is at data-space `0x8000–0xFFFF` and is 32 KB wide**, i.e. one of the four
  quarters of ROM1 at a time. **At reset it shows file `0x08000–0x0FFFF`** (bank 1 below - the
  v3.0 firmware copy), and that is *uniquely* determined: it is the only quarter for which
  all three window reads on the boot path come out right -
  `0x800F` is not `'C'` (option-ROM probe at 0x8251 must fail),
  `0xC063` matches ROM2's control-code dispatch table byte-for-byte over 64 bytes
  (`ctrl_lookup` @0xC2C0 fetches it through the window), and
  `0x8100` is the run of NULs at the head of the power-on command stream.
  See THEORY_OF_OPERATION.md §0a for the table.
  🔶 The bank field looks like gate-array **reg2 bits 7-6** with quarter = `(bank + 2) & 3`
  (reset leaves reg2 = 0xD0 → bank 3 → quarter 1), but that mapping rests on the single reset
  anchor and is **not** corroborated by the font descriptor blocks - byte 3 of all four
  descriptors at 0x10110/0x10150/0x10190/0x101D0 reads 0x00, so the "rec byte3 & 3 = bank"
  note further down needs re-checking.
- IC4 LS373 = AD latch; IC9 BR93C46 = serial EEPROM (live EDS settings). ✅

---

## ROM2 - firmware, 32 KB  (file 0x0000–0x7FFF ↔ CPU 0x8000–0xFFFF)
Version `*** VER 3.2 ***` (string at file 0x7FD0). ~22 KB code, ~10.5 KB data. ✅

### Vectors (file 0x7FF4–0x7FFF) ✅
```
FFF4 TX/CNTR/BRK -> 501A      FFFA RI/INT1 -> 5057
FFF6 HE/VE       -> 5046      FFFC INT2    -> 505F
FFF8 Timer1/2/3  -> 4965      FFFE RESET   -> 8130
```
All IRQ targets (0x49xx–0x50xx) are in the **ROM1 system region** (CPU 0x4000–0x7FFF). ✅
Note: 0x5057 (RI/INT1) is an unused-source error trap; 0x505F (INT2) = host /IN-PRIME reset.

### Structure (file offsets) ✅
| file | CPU | size | kind |
|------|-----|------|------|
| 0x0000–0x007F | 8000–807F | 128 B | ✅ **factory default EDS record** - 64 big-endian 16-bit words. `sub_7841` copies all 64 to EEPROM words 0x00–0x3F whenever the stored settings fail their signature check, so a blank BR93C46 self-initialises. Word 0x3F = `0x807E/0x807F` = **`4E 03`** is the signature the reset path compares against at 0x81D1/0x81D9 |
| 0x0080–0x012F | 8080–812F | 176 B | DATA - header/jump table at reset region |
| 0x0130–0x0761 | 8130–8761 | 1586 B | CODE - **reset/init** (stack, WDT, RAM test, port setup) |
| 0x0762–0x1480 | … | mixed | CODE with small DATA tables interleaved |
| ~0x1480–0x3844 | … | large | many DATA tables (incl. 0x242E–0x2B47, 0x2C28–0x3844) interleaved with code ❓ |
| 0x3845–0x7E34 | B845–FE34 | bulk | mostly CODE (print engine, ESC/P parser, menus) |
| 0x7E35–0x7ED4 | FE35–FED4 | 160 B | DATA table |
| 0x7F00–0x7FA6 | FF00–FFA6 | - | CODE in **special page** (2-byte `JSR` targets) |
| 0x7FA7–0x7FFF | FFA7–FFFF | 88 B | DATA - special-page pointers + vectors |

### Notable strings (file offset) ✅
- 0x3F36 `BI-DIRECTIONAL SETTING`, 0x3FB2 `CURRENT ELECTRONIC DIP SWITCH (EDS) SETTINGS`,
  0x3FE0 switch grid, 0x400D `Bank A B C D`
- 0x463E `*** DOT ADJUSTMENT SETTING ***`, 0x465E `*** END ***`,
  0x46E5 `UNI +8 +7 … -8` (bidirectional alignment menu)
- 0x7FD0 `*** VER 3.2 ***`

---

## ROM1 - font/system ROM, 128 KB  (four 32 KB banks, MA bus)
Bank fill profile: b0 24%·0, b1 3%·0, b2 16%·0, b3 49%·0. ✅

### Bank 0 - 0x00000–0x07FFF : RAM-overlap data + **CPU system code** + help text
NOTE: **0x04000–0x07FFF is mapped into CPU program space at 0x4000–0x7FFF (DME off)** and
holds the **interrupt service routines + core subroutines** (see "CPU system ROM" below).
0x00000–0x03FFF is the font/data half (CPU 0x0000–0x3FFF is RAM, so this half is reached only
via the DME/font path).
| file | kind |
|------|------|
| 0x00000–0x07FFF | ✅ **Orator + Script 16-dot NLQ glyph data** (planar). Reached via bank2 metrics tables 0x168f1+/0x17471+ with map `file = ptr-0x8000`. Orator=bold caps, Script=cursive. Sheets: FONT_orator.png / FONT_script.png. (0x04000–0x07FFF still doubles as CPU code in program space - the glyph reads use the DME/font path.) |
| 0x04000–0x05645 | ✅ **CPU code** (ISRs @CPU 0x4965/0x501A/0x5046/0x5057/0x505F; core routines e.g. get_rx_byte@64B7) |
| ~0x05A0B–0x063xx | ✅ **motor accel/decel ramp streams** - 11 profiles x 2 (accel @ptr table 0x443B, decel @0x4451), byte streams of per-stage dwell-tick counts consumed by the timer ISR (see THEORY §9a) |
| 0x06BDB–0x071DC | ✅ **EDS self-test menu TEXT** (human-readable): `EDS SETTINGS`, Emulation STANDARD, RAM Usage, Auto-LF, ASF, Print Mode (10cpi Draft/HS-Draft/17cpi/COURIER), Page Length, Character Table, **International Char Sets** (USA/Denmark/France/Sweden/Germany/Italy/England/Spain), **IBM Code Pages** (#437/#863/#850/#865/#860/#861) |
| 0x07455–0x074xx | ✅ self-test sample text: `0123456789`, `*** This is first line. ***`, `*** This is line` |

### Bank 1 - 0x08000–0x0FFFF : **FIRMWARE v3.0** ✅
86.4% identical to ROM2; byte-identical IRQ vectors; string `*** VER 3.0 ***` at 0x0FFD0.
An **older copy of the program** (ROM2 = updated v3.2). Same layout shifted by +0x8000.

### Bank 2 - 0x10000–0x17FFF : **METRICS + DESCRIPTOR tables (NO glyph bitmaps here)** ✅
The coverage audit shows bank 2 is essentially all tables, not bitmaps.
| file | finding |
|------|---------|
| 0x10000–~0x102xx | ✅ **font DESCRIPTOR blocks** (0x40 B each) + index: idx 0x14/0x1e/0x28/0x32 at file 0x10110/0x10150/0x10190/0x101D0 (= Courier/Sanserif/Orator/Script). `rec byte3 & 3` = glyph-data bank. |
| 0x10300–0x12700 | ✅ **3-byte descriptor/index tables** ('00 XX' / 'BC 00 00' / '01 00 XX' entries) - the per-char glyph-pointer chains, NOT fixed-cell bitmaps (earlier "stride 12/24 fixed-cell fonts" guess was wrong; these are pointer tables). |
| 0x12A81–~0x14C19 | ✅ **8-dot Draft metrics tables** (8 B/char) - two parallel 585-entry groups (Draft @0x12771, HS-Draft @0x139C1), faces at identical entry offsets, selected by font idx (HS flag → group 1 @0x86EC; elite → idx+1 @0x8729). Identified: **0x132C1 = Draft Pica** (w≤11), **0x12B91 = Draft Elite** (9-wide), **0x14509 = HS-Draft Pica** (9-wide), **0x13DE1 = HS-Draft Elite** (w≤7). Condensed = programmatic transform (not stored). Draft companions @0x13129/0x13851; HS companions @0x14379/0x14AA1. |
| 0x14C19–0x17FFF | ✅ **16-dot NLQ metrics tables**: Courier 0x14F21, Sanserif 0x15C81, Orator 0x168F1, Script 0x17561 (+ IBM-symbols 0x14E21, box-graphics 0x15851 supplements). |

### Bank 3 - 0x18000–0x1FFFF : **8-dot Draft glyph data + Courier/Sanserif NLQ data** ✅
| file | finding |
|------|---------|
| 0x183B8–~0x1A0A0 | ✅ **8-dot Draft + HS-Draft glyph bitmaps** (1 B/col, bit7=top). Draft Pica @**0x18AA2**, Draft Elite @0x184C3, HS-Draft Elite @0x1964C, HS-Draft Pica @0x19AF7, + companions (reached via the bank2 metrics tables, `file = ptr+0x10000`). Sheets: FONT_draft.png + SET_8dot_*.png. |
| 0x1A0D7–0x1FFFF | ✅ **Courier + Sanserif 16-dot NLQ glyph data** (planar, 2 B/col). `file = ptr+0x10000`. Sheets: FONT_courier.png / FONT_sanserif.png. (Orator/Script NLQ data is in **bank 0**, see above; they wrap bank3→bank0 mid-alphabet.) |

### Confirmed font bit-format (proportional sets) ✅
Column-major, 1 byte/column, **bit7 = top pin**, 8 dots tall, glyphs packed back-to-back
with per-character **proportional width**.

### ✅ RESOLVED: width source = the 8-byte-per-char METRICS TABLES (bank 2)
Each font has an 8-byte/char metrics table in bank 2. Entry = `[glyph_ptr(2B), rec2, rec3,
rec4, rec5, rec6, rec7]`. **WIDTH = ptr(c+1) − ptr(c)** (glyphs packed contiguously).
- `rec2` = in-cell **bearing**: hi nibble = LEFT space, lo nibble = right space, and
  `left + width + right` = the cell (12 half-boxes for 8-dot draft, 24 quarter-boxes for 16-dot
  NLQ = 6 boxes either way). This seats narrow glyphs correctly in their monospace cell.
- `rec4` bit7 = **descender flag** (clear → g/p/q/y stored 1 row high, render shifted down).
8-dot glyph file offset = `ptr + 0x10000` (bank 3) for the draft sets; 16-dot NLQ uses the
wrap-aware continuous-file walk (glyphs are laid out contiguously across the 128 KB; the
file offset wraps mod 0x20000 at the bank3→bank0 seam).

---

## ✅ COVERAGE AUDIT
ROM1 accounted for: firmware bank1 **25%**, system code (ISRs) **12.5%**, glyph bitmaps
(5 NLQ/draft faces + the 8-dot pitch sets) **~31%**, metrics/descriptor + 3-byte ptr tables
**~18%**. **Glyph-bitmap extraction ≈ 88%**; the remaining ~4% "glyph-like" is mostly
3-byte pointer/descriptor tables, not bitmaps (only ~1.5 KB @0x17E00 is an ambiguous bitmap
remnant). In summary: bank0 0x00000–0x03FFF = Orator/Script NLQ data; bank2
0x11000/0x12000 = pointer tables (not fixed-cell fonts); the 0x10000 record table = font
descriptor blocks (idx→bank). **CP437 confirmed** (the 0x80+ glyphs match the users manual's
Ch.9 chart). Full stored-font list: Draft (pica+elite) + HS-Draft (its own pica+elite) +
Courier/Sanserif/Orator/Script (italic = programmatic slant); condensed = programmatic
transform.

## Beeper
- `beep_tone`@6466 (gate-array beeper reg + Timer1 + duration mem_0008/09); presets
  `beep_short`@63ac / `beep_key`@63b7 / `beep_med`@63c2 / `beep_long`@63cd; host BEL = `ctl_BEL`@639A.
- No power-on beep unless a panel button is held (dispatcher @0x844C calls `beep_key`).
- `beep_paper_out`@63da: the paper-out alarm, 4 beeps, pause, 4 beeps (duration 0x00CC each,
  inter-beep gap 0x32 delay units, group gap ~7x that). Checks `panel_read` between groups and
  aborts with carry set if a button is pressed. Called from the P0.6 paper-end test @0x72DD and
  the debounced recheck @0xD270.
