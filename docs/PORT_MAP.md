# NX1020 - M50734 port / hardware bit map

Sources: ✅ datasheet (Mitsubishi_justM50734.pdf), ✅ ROM2 init code, 🔶 schematic, ❓ to confirm.

## Special-function registers (zero page) used by firmware
| Addr | Name | Notes |
|------|------|-------|
| 0xEC | PHASECNT | Vertical+Horizontal stepper phase counter |
| 0xED | P2P3FUNC | Port P2/P3 function select |
| 0xEE / 0xEF | P3 / P3DIR | Port P3 data / direction |
| 0xF0 / 0xF1 | P2 / P2DIR | Port P2 data / direction (stepper motors) |
| 0xF2 / 0xF3 / 0xF4 | P1IN / P1 / P1DIR | Port P1 latched-input / data / direction |
| 0xF5 / 0xF6 / 0xF7 | P0FUNC / P0 / P0DIR | Port P0 function / data / direction |
| 0xF8 / 0xF9 | SMCONH / SMCONV | Stepper-motor control H (carriage) / V (line-feed) |
| 0xFC | WDT | Watchdog timer (write 0xFF to kick) |
| 0xFD / 0xFE / 0xFF | ICON3 / ICON2 / ICON1 | Interrupt control registers |

## Port P0 (0xF6, dir 0xF7, func 0xF5) - control / handshake / mem-expand
Per-bit dual function selected by `P0FUNC` (1 = special function):
| Bit | Normal | Special (P0FUNC bit=1) | Schematic role |
|----|--------|------------------------|----------------|
| 0 | P0.0 | **INT1** (ext interrupt) | ❓ host STROBE / event in |
| 1 | P0.1 | **INT2** (ext interrupt) | ❓ |
| 2 | P0.2 | **CNTR** (Timer I/O) | ❓ |
| 3 | P0.3 | **BUSYOUT** | 🔶 Centronics BUSY (via LS05, CPU pin 41) |
| 4 | P0.4 | **STBOUT** | 🔶 strobe pulse out |
| 5 | P0.5 | **DME** (data-memory enable) | ✅ enables 2nd 64K data space = **font-ROM bank access** |
| 6 | P0.6 | **TxD** (UART tx) | serial out |
| 7 | P0.7 | **RxD** (UART rx) | serial in |

Init: `P0FUNC=0x20` → only **P0.5=DME** special. `P0DIR=0x38` → P0.3/4/5 outputs.
Later `seb 4,P0` drives P0.4 high.

## Port P1 (0xF3, in-latch 0xF2, dir 0xF4) - role unconfirmed ❓ (NOT host data)
CORRECTION (manual p20): host parallel data is latched by the **GATE ARRAY** at STROBE-fall and
read by the CPU from the gate array via DB7/IA7 - **NOT** via P1. So the earlier "P1 = host data
latch" guess is wrong. P1's actual use is unconfirmed. Init `P1DIR=0x07` → P1.0-2 out, P1.3-7 in.

## Port P2 (0xF0, dir 0xF1) - STEPPER MOTORS ✅
Two 4-bit channels (`P2.0-3` = P2L, `P2.4-7` = P2H), four-phase outputs, selected by
`P2P3FUNC` bits 6-7. Drives carriage (`SMCONH`) and line-feed (`SMCONV`) motors via `PHASECNT`.
Init: `P2DIR=0xFF` (all outputs), `P2=0x90` (initial phase pattern), `PHASECNT=0`.

## Port P3 (0xEE, dir 0xEF) - MOTOR DRIVE-VOLTAGE SELECTS ✅ (corrected per manual p26-28)
| Bit | Role |
|----|------|
| 0 (P30) | **Carriage-motor voltage select** (TR1/TR6): HIGH=+25 V drive / LOW=+5 V holding bias |
| 1 (P31) | **Paper-feed-motor voltage select** (TR4/TR5): +25 V drive / +5 V holding bias |
Init: `P2P3FUNC=0x04` (Timer-S source = f/16; P2 four-phase normal), `P3DIR=0x03` → P3.0/1 outputs.
NOTE: the earlier guess "P3.0=PWM, P3.1=EEPROM SCLK" was wrong. The BR93C46 EEPROM serial lines
(CS/CLK/DI/DO) are therefore on other pins - not yet identified (read in init via sub_771d).
P3.7 is read as an input in the feed/print code (a sensor - paper-end or tractor; see detectors).

## Port P4 (0xEB) - 4-bit input / analog ✅
4-bit input port (also A-D AN0-3). One analog channel = the **print-head thermistor** (thermal
protection: ≤115 °C normal / 115-125 °C interval / ≥125 °C stop - manual p25). Others likely
the home-position photo-interrupter / paper-end reflective sensor / tractor & release leaf switches.

## Interrupt control (init)
`ICON1`: set bit2, clear 3/4/5.  `ICON2`: clear 0-5.  `ICON3`: set bit2.
→ enables the Timer1/2/3 group (vector 0xFFF8) used for motor/print timing; masks the rest.

## Gate array & hardware output ✅ (from firmware)
- A custom **gate array** is memory-mapped at **0x4000–0x4003 in the DME data space**.
  **P0.5 = DME** gates every access (`seb 5,P0FUNC` before each). Pointer `mem_00ae:af = 0x4000`.
- It is the I/O hub between CPU ⇄ **font ROM** (MA0–16 bus) ⇄ **print head** (HD0–9/HDEN).
- Special-page I/O primitives (all toggle DME): `ff4a`=write reg0 (head/data), `ff58`=reg1
  (cached in mem_00bb), `ff51`=reg2, `ff61`=reg3; `ff33`=read reg2, `ff3d`=read reg3
  (status), `ff3a`=cached reg1.
- **STBT** (Timer S, 0xFA) = head-strobe pulse width. Init writes `0xAA/0x55` to reg0 =
  print-head shift-register test.
- **Carriage sweep** polls the encoder on **P0.7** (both edges → 2 dot-columns/box = the
  half-step pitch); `SMCONH` bit1 steps the carriage motor at line end. `HCNT` = column count.
- The **real-time per-dot firing & motor micro-stepping** are in the timer/HE-VE ISRs, which
  live in **ROM1 mapped at CPU 0x4000–0x7FFF** (NOT RAM): `isr_timer123`@4965, `isr_he_ve`@5046
  (reload HCNT, pulse SMCONH per column), `isr_ri_int1`@5057 (host rx), `isr_int2`@505F
  (emergency stop). Now traced in `rom2_labeled.asm`.

## Schematic-confirmed external nets ✅
- Centronics out via LS05 (IC2): ACK=pin43, BUSY=pin41, PE=pin40, SEL=pin39, ERR; STB in=pin52.
- VDD=64, GND=32/53. LS373 (IC4) latches A0-A7 from the multiplexed AD bus.
- Font ROM (IC7 D27C1001) on MA0-MA16, gated by **DME (P0.5)**. RAM=IC5, firmware=IC6.
- EEPROM IC9 BR93C46, serial interface (exact CPU pins not yet identified - see Port P3 note).
