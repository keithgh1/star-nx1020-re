# NX1020 control-code & ESC command tables (decoded from ROM2)

Lookup: `sub_c2c0` walks a table of 3-byte entries `[char, lo, hi]`, 0x00-terminated;
on match it `jmp [addr]`. The active table is chosen by char-set mode (bit7 of EDS @0x0053).
A handler of **0x8533** = main loop = command accepted but ignored in that emulation.

## C0 control codes
STD table @0xC063, IBM table @0xC091 (handlers: BEL=639A BS=A076 HT=AF25 LF=953E
VT=B15A FF=9687 CR=94BE SO=9DC3 SI=98F9/9A0B DC1=A03E DC2=9924/99BC DC3=A036/ignored
DC4=9DC8 CAN=A010 ESC=dispatch C0BF/C1BC).

## ESC commands  (STD table @0xC0D4, IBM table @0xC1D8)

| ESC | meaning | STD handler | IBM handler |
|-----|---------|-------------|-------------|
| `^0A` | ESC LF | 966C | (ignored) |
| `^0C` | ESC FF | 96D6 | (ignored) |
| `^0E` | ESC SO one-line double-width | 9DC3 | 9DC3 |
| `^0F` | ESC SI condensed | 98F9 | 9A0B |
| `^19` | ESC EM paper/ASF ctl (subcommand dispatch, incl. undocumented - see "ESC EM subcommands" below) | BCC0 | BCC0 |
| `^1A` | ESC SUB repeat char (IBM) | C042 | C042 |
| ` ` | ESC SP intercol space | AA07 | - |
| `!` | ESC ! master print mode | 9715 | (ignored) |
| `#` | ESC # accept 8th bit | A97E | (ignored) |
| `$` | ESC $ abs horiz position | AA16 | (ignored) |
| `%` | ESC % select user/ROM font | B9C6 | (ignored) |
| `&` | ESC & define download chars | B300 | (ignored) |
| `*` | ESC * select bit image | A452 | (ignored) |
| `-` | ESC - underline on/off | 9DE0 | 9DE0 |
| `/` | ESC / select VTAB channel | B237 | (ignored) |
| `0` | ESC 0 line spacing 1/8in | 9E4F | 9E4F |
| `1` | ESC 1 line spacing 7/72in | 9E53 | 9E53 |
| `2` | ESC 2 line spacing 1/6in | 9E57 | 9E5C |
| `3` | ESC 3 line spacing **n/216** (9-pin; stores n×2 of 1/432" units) | 9E64 | 9E64 |
| `4` | ESC 4 italic on | 9DEC | 9F61 |
| `5` | ESC 5 italic off | 9DF3 | 9520 |
| `6` | ESC 6 enable upper chars | 97BA | 97C9 |
| `7` | ESC 7 disable upper chars | 97C1 | 97D0 |
| `8` | ESC 8 paper-out det off | A045 | A045 |
| `9` | ESC 9 paper-out det on | A04D | A04D |
| `:` | ESC : copy ROM font to RAM | B9E4 | 99E4 |
| `<` | ESC < one-line unidir | AA00 | (ignored) |
| `=` | ESC = clear MSB | A972 | B5CA |
| `>` | ESC > set MSB | A978 | (ignored) |
| `?` | ESC ? reassign bit-image mode | AAD9 | (ignored) |
| `@` | ESC @ reset printer | 9FE9 | 9FE9 |
| `A` | ESC A line spacing n/72 | 9E79 | 9E79 |
| `B` | ESC B set VTAB stops | B096 | B096 |
| `C` | ESC C page length | 9EF7 | 9EF7 |
| `D` | ESC D set HTAB stops | AEAA | AEAA |
| `E` | ESC E emphasized on | 9C54 | 9C54 |
| `F` | ESC F emphasized off | 9C34 | 9C76 |
| `G` | ESC G double-strike on | 9C9E | 9CA9 |
| `H` | ESC H double-strike off | 9CA3 | 9CA3 |
| `I` | ESC I expand char set (IBM) | AC4A | 9ABE |
| `J` | ESC J one-time **n/216** feed | A985 | A985 |
| `K` | ESC K 60dpi bit image | A45B | A45B |
| `L` | ESC L 120dpi bit image | A460 | A460 |
| `M` | ESC M elite 12cpi | 98E8 | 99E5 |
| `N` | ESC N set skip-perforation | 9F66 | 9F66 |
| `O` | ESC O cancel skip-perf | 9F8F | 9F8F |
| `P` | ESC P pica 10cpi | 98D4 | 9D5A |
| `Q` | ESC Q right margin / deselect | AC4F | A02B |
| `R` | ESC R intl char set | 9816 | AEA4 |
| `S` | ESC S super/subscript | 9CC2 | 9D04 |
| `T` | ESC T cancel super/sub | 9CEE | 9D3C |
| `U` | ESC U unidirectional on/off | A965 | A965 |
| `W` | ESC W double-width on/off | 9DD0 | 9DD0 |
| `X` | ESC X select font/pitch | (ignored) | AE80 |
| `Y` | ESC Y 120dpi double-speed img | A465 | A465 |
| `Z` | ESC Z 240dpi bit image | A46A | A46A |
| `[` | ESC [ (ext cmd) | 9844 | A1F7 |
| `\` | ESC \ relative horiz position | A643 | A054 |
| `^` | ESC ^ 9-pin bit image | A440 | A06C |
| `_` | ESC _ overscore on/off | (ignored) | 9DFE |
| `a` | ESC a justify/align | 9F9B | (ignored) |
| `b` | ESC b set VTAB in channel | B09A | (ignored) |
| `c` | ESC c (HMI / set width?) | 9F34 | 9F34 |
| `e` | ESC e (set tab unit?) | A84A | (ignored) |
| `f` | ESC f (skip h/v space?) | A7F1 | (ignored) |
| `h` | ESC h enlarge/expand size | A144 | (ignored) |
| `j` | ESC j reverse line feed | A9C4 | (ignored) |
| `k` | ESC k select LQ typeface | 9D85 | 9D85 |
| `l` | ESC l left margin | AD4D | (ignored) |
| `p` | ESC p proportional on/off | 9D5D | (ignored) |
| `r` | ESC r (color - n/a) | 9EB5 | 9EB5 |
| `s` | ESC s half-speed on/off | AC30 | (ignored) |
| `t` | ESC t select char table | 97D8 | 97D8 |
| `w` | ESC w double-height | A19A | (ignored) |
| `x` | ESC x draft/LQ select | 9941 | (ignored) |
| `z` | ESC z (?) | 9977 | 9977 |
| `~` | ESC ~ (?) | A01E | (ignored) |

## ESC EM subcommands (dispatch @0xBCC5) - traced Aug 2026

Gate: **mem_0052 bit 7 = "ASF installed"** (EDS switch A-4 OFF); every ASF subcommand is
ignored when clear. **mem_0052 bit 6 = "ASF selected"** (consumed at the paper-load /
form-feed / feed-sequence decision points 0x8674, 0x926D, 0x96B2, 0xD4EE; bit 7 itself is
checked at ~45 sites across the feed engine).

Documented in the users manual (p85-86):
| n | Function | Firmware |
|---|----------|----------|
| 0 / '0' | Deselect ASF (manual feed) | `clb 6,mem_0052` |
| 4 / '4' | Select ASF | `seb 6,mem_0052` |
| 'R' | Eject current sheet | `jmp ctl_FF` (form-feed path ejects when ASF selected) |
| 'T' n | Skip n/6 inch at top of ASF page (n = 1-15) | @0xBD0C: feed distance = ROM default (mem_8128/29) + (n-6) x 72 steps (72 steps = 1/6"); n masked to 4 bits, 0 treated as 1 |

UNDOCUMENTED extensions (not in the users manual):
| n | Function | Firmware |
|---|----------|----------|
| 'C' n | Color select - alias of `ESC r n` | `jmp cmd_esc_r` |
| 'F' n | Resident font select by descriptor index | @0xBC2F: accepts '0'-'9' (masked) or raw index < 0x40; looks up the descriptor table at DME 0x8010 (bank via `sub_f676`), rejects 0xFF entries, stores (id - 3) into mem_0059 bits 0-2, applies via sub_9E0B |
| 'S' n | Double-height / size control | @0xBC7F: n bit 0 -> mem_0063.0 + mem_007b.3; n bit 1 routes into `cmd_esc_w`'s ON (0xA19E) / OFF (0xA1C5) apply paths |
