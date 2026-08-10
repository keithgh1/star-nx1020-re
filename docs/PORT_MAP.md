# NX1020 - M50734 port / hardware bit map

Sources: ✅ datasheet (Mitsubishi_justM50734.pdf), ✅ ROM2 firmware, ✅ technical manual,
✅ schematic (pin-level trace, Aug 2026). All CPU port pins are now accounted for.

## Special-function registers (zero page) used by firmware
| Addr | Name | Notes |
|------|------|-------|
| 0xE9 | ADCON | A-D control: bits 0-1 = channel select, bit 2 = start (write) / complete (read) |
| 0xEA | ADR | A-D result register |
| 0xEB | P4 | Port P4 digital read (low 4 bits) |
| 0xEC | PHASECNT | Vertical+Horizontal stepper phase counter |
| 0xED | P2P3FUNC | Port P2/P3 function select |
| 0xEE / 0xEF | P3 / P3DIR | Port P3 data / direction |
| 0xF0 / 0xF1 | P2 / P2DIR | Port P2 data / direction (stepper motors) |
| 0xF2 / 0xF3 / 0xF4 | P1IN / P1 / P1DIR | Port P1 latched-input / data / direction |
| 0xF5 / 0xF6 / 0xF7 | P0FUNC / P0 / P0DIR | Port P0 function / data / direction |
| 0xF8 / 0xF9 | SMCONH / SMCONV | Stepper-motor control H (carriage) / V (line-feed). SMCONH bit 1 = carriage direction: clear = left-to-right pass, set = right-to-left (render code keys column reversal off it) |
| 0xFC | WDT | Watchdog timer (write 0xFF to kick) |
| 0xFD / 0xFE / 0xFF | ICON3 / ICON2 / ICON1 | Interrupt control registers |

## Port P0 (0xF6, dir 0xF7, func 0xF5) - handshake, DME, sensors ✅
Per-bit dual function selected by `P0FUNC` (1 = special function).
Init: `P0FUNC=0x20` (only P0.5 = DME special), `P0DIR=0x38` (P0.3/4/5 outputs, rest inputs).

| Bit | Mode | Role |
|----|------|------|
| 0 | port, in | **/RELEASE** release-lever leaf switch (4.7k pullup + 4.7k series). Open = HIGH = lever in friction position; closed = LOW = lever in tractor position (manual p36). INT1 special function unused: interrupt masked, its vector holds an error trap (see below). |
| 1 | special | **/INT2 = /IN-PRIME**, Centronics pin 31 (active low). Host pulses LOW to reset the printer. `isr_int2`@505F shuts off head + motors, spin-waits for the line to return HIGH (`bbc 1,P0` @0x5099, kicking WDT), then re-initializes. |
| 2 | port, in | **/TRACTOR** tractor-position leaf switch (same pullup + series circuit as bit 0). Open = HIGH = tractor up (pull-tractor); closed = LOW = tractor down (push-tractor) (manual p36). CNTR special function unused. |
| 3 | BUSYOUT | Centronics BUSY (via LS05, CPU pin 41) |
| 4 | STBOUT | print-head energize strobe: drive LOW to fire; `STBT` (Timer S, 0xFA) sets the solenoid pulse width |
| 5 | DME | data-memory enable: gates the 2nd 64K data space = gate-array + font-ROM window |
| 6 | port, in | **PE** paper-end reflective sensor. LED always on (220R to GND); phototransistor emitter output into P0.6. **HIGH = paper present.** TxD special function unused. |
| 7 | port, in | **HP** home-position photo-interrupter (pullup on phototransistor collector). **HIGH = beam blocked = carriage shield at home.** Polled only by the home-seek routine (`sub_d840`); there is no carriage encoder - sweep pacing is open-loop, timer-driven. RxD special function unused. |

The release/tractor pair encodes the paper-feed mode (manual Fig. 2-23, p35):

| P0.0 (release) | P0.2 (tractor) | Mode |
|---|---|---|
| HIGH (friction pos.) | LOW (tractor down) | Friction feed (single sheets) |
| HIGH (friction pos.) | HIGH (tractor up) | invalid - manual marks it "(Error)" |
| LOW (tractor pos.) | LOW (tractor down) | Push tractor |
| LOW (tractor pos.) | HIGH (tractor up) | Pull tractor |

Checked throughout the feed/print code (~28 sites). The frequent paired tests that branch
away when either bit is HIGH (e.g. 0x9666, 0xC7E0, 0xCD53) are "not push-tractor" checks:
push-tractor is the only both-LOW state.

## Port P1 (0xF3, in-latch 0xF2, dir 0xF4) - EEPROM serial interface ✅
The BR93C46 EEPROM (IC9) is bit-banged on P1. Init `P1DIR=0x07` (P1.0-2 out, P1.3-7 in).

| P1 bit | BR93C46 pin | Signal | Firmware primitive |
|---|---|---|---|
| 0 | 1 | CS | `sub_ff6e` set / `sub_ff71` clear |
| 1 | 2 | SK (clock) | `sub_ff7a` = one full clock pulse (raise, delay, drop; kicks WDT) |
| 2 | 3 | DI | `sub_ff74` set / `sub_ff77` clear |
| 4 | 4 | DO | sampled via `bbc 4,P1` in the read loops |
| 3 | 6 | NC/ORG | wired to the CPU but inert: firmware never accesses P1.3 (left as input) |

Pins 5/8 = GND/VCC. Transactions are 16-bit, matching the 64x16 organization:
`eeprom_read` @0x771D shifts two bytes into mem_0159/015a; `eeprom_write` @0x775D shifts
them out. Read in init via 0x771D (settings/EDS record).

Datasheet note: P1 has a transparent input latch (0xF2) captured when the INT1 pin goes low,
i.e. the chip's *intended* use is Centronics-style data-on-P1 / strobe-on-INT1. Star did not
use it: host data goes through the gate array, and P1 was repurposed as EEPROM GPIO. This is
where the early (wrong) "P1 = host data latch" guess came from.

## Port P2 (0xF0, dir 0xF1) - STEPPER MOTORS ✅
Two 4-bit channels (`P2.0-3` = P2L, `P2.4-7` = P2H), four-phase outputs, selected by
`P2P3FUNC` bits 6-7. Drives carriage (`SMCONH`) and line-feed (`SMCONV`) motors via `PHASECNT`.
Init: `P2DIR=0xFF` (all outputs), `P2=0x90` (initial phase pattern), `PHASECNT=0`.

## Port P3 (0xEE, dir 0xEF) - motor voltage selects + control panel ✅
Init: `P2P3FUNC=0x04` (Timer-S source = f/16; P2 four-phase normal), `P3DIR=0x03` (P3.0/1 out).

| Bit | Role |
|----|------|
| 0 | **CR CMN A/B voltage select** (carriage-motor commons, TR1/TR6): HIGH = +25 V drive / LOW = +5 V holding bias |
| 1 | **LF CMN A/B voltage select** (paper-feed-motor commons, TR4/TR5): same scheme |
| 2 | unconnected ✅ (absent from the schematic; firmware never accesses it; SIO special function unused) |
| 3 | **/FONT** button |
| 4 | **/PITCH** button |
| 5 | **/SET** button |
| 6 | **/PF** (paper feed) button |
| 7 | **/OL** (on line) button |

Panel buttons are active low: each switch shorts its line to ground, pullups in resistor
array RA3, 4.7k series into the CPU pin. Scanned by `panel_read` @0xFF8F: read P3 until two
consecutive reads match (debounce), then `AND #0xF8` to isolate the 5-bit button field.
Only /PF and /OL are also tested as individual bits (mid-job pause/feed, and the power-on
held-button checks @0x4E11 for self-test / hex dump).
Superseded guesses: "P3.0 = PWM / P3.1 = EEPROM SCLK" (EEPROM is on P1) and "P3.7 = paper
sensor" (it is the On Line button).

## Port P4 (0xEB, A-D in AN0-3) - head thermistor only ✅
Only **P4.3/AN3** is connected: the print-head thermistor. TH+ to 5 V, thermistor down to a
node with 10k to ground and a filter cap, into P4.3. NTC, so hotter = higher reading.
The single A/D sequence in the firmware (`head_thermal_check` @0xD990) selects channel 3
(ADCON bits 0-1 = 11), starts a conversion (bit 2), polls complete, reads ADR (0xEA), then:
- **>= 0xFC or < 0x04**: thermistor short / open -> fatal error trap (`lab_7d5c` family)
- **>= 0xDA** (~125 C): stop - mask head output via the gate array, long WDT-kicked waits,
  re-measure until it cools below threshold
- **0xD1-0xD9** (~115-125 C): "interval printing" - 10x pause calls per check (the manual's
  ~0.5 s/line head cooling pause)
- **< 0xD1**: normal printing
P4.0-2 are unconnected.

## Interrupt control ✅ (datasheet Fig.3 + init code)
- `ICON1` (0xFF): b7/b6 = VE request/enable, b5/b4 = HE request/enable,
  **b3/b2 = /INT2 request/enable**, b1/b0 = /INT1 request/enable.
- `ICON2` (0xFE): b5/b4 = Timer3 request/enable, b3/b2 = Timer2, b1/b0 = Timer1.
- `ICON3` (0xFD): b7/b6 = CNTR request/enable, b5/b4 = TimerX request/enable, b3 = CNTR
  polarity, b2 = TimerX count-stop, b1/b0 = TimerX mode.

Init decodes as: `ICON1` set b2 = **enable /INT2 (host IN-PRIME)**, clear b3 (stale request)
and b4/b5 (HE masked); `ICON2` clear b0-b5 = all Timer1/2/3 interrupts off (the motion code
enables them when a move starts); `ICON3` set b2 = Timer X count stopped.
So at power-up only the host IN-PRIME interrupt is armed. (Earlier note "init enables the
Timer1/2/3 group" was wrong: ICON1 bit 2 is the INT2 enable, and the timers live in ICON2.)

**Datasheet erratum**: Table 1 (interrupt vectors) prints "INT1" for BOTH priority 2 and
priority 3. Resolution (Fig.3 ICON1 bit names + firmware behavior + schematic): 0xFFFC =
**/INT2** and 0xFFFA = **RI or /INT1**; m740dasm's vector naming is correct. The 0xFFFA
handler (`isr_ri_int1` @0x5057) is an unused-source trap: long beep, then the fatal-error
path @0x7D55. It is NOT the host-receive path - host bytes are polled from the gate array.

## Gate array & hardware output ✅ (from firmware)
- A custom **gate array** is memory-mapped at **0x4000-0x4003 in the DME data space**.
  **P0.5 = DME** gates every access (`seb 5,P0FUNC` before each). Pointer `mem_00ae:af = 0x4000`.
- It is the I/O hub between CPU ⇄ **font ROM** (MA0-16 bus) ⇄ **print head** (HD0-9/HDEN).
- Special-page I/O primitives (all toggle DME): `ff4a`=write reg0 (head/data), `ff58`=reg1
  (cached in mem_00bb), `ff51`=reg2, `ff61`=reg3; `ff33`=read reg2, `ff3d`=read reg3
  (status), `ff3a`=cached reg1.
- **STBT** (Timer S, 0xFA) = head-strobe pulse width. Init writes `0xAA/0x55` to reg0 =
  print-head shift-register test.
- **Carriage homing**: `home_seek` (`sub_d840`) checks HP on P0.7; if not home, starts the
  carriage (SMCONH bit1) with a step budget and waits for P0.7 to go HIGH (double-read
  debounce), reversing/retrying via 0xD8B6 if the budget runs out, then edge-aligns with
  alternating high/low waits. `HCNT` = column count during sweeps.
- The **real-time per-dot firing & motor micro-stepping** are in the timer/HE-VE ISRs, which
  live in **ROM1 mapped at CPU 0x4000-0x7FFF** (NOT RAM): `isr_timer123`@4965, `isr_he_ve`@5046
  (reload HCNT, pulse SMCONH per column), `isr_int2`@505F (host IN-PRIME reset),
  `isr_ri_int1`@5057 (unused trap). Traced in `rom2_labeled.asm`.

## Schematic-confirmed external nets ✅
- Centronics out via LS05 (IC2): ACK=pin43, BUSY=pin41, PE=pin40, SEL=pin39, ERR; STB in=pin52;
  /IN-PRIME (CN1 pin 31) -> P0.1.
- VDD=64, GND=32/53. LS373 (IC4) latches A0-A7 from the multiplexed AD bus.
- Font ROM (IC7 D27C1001) on MA0-MA16, gated by **DME (P0.5)**. RAM=IC5, firmware=IC6.
- EEPROM IC9 BR93C46 on **P1** (P1.0=CS, P1.1=SK, P1.2=DI, P1.4=DO; P1.3 to pin 6, inert).
- Sensors/switches: PE sensor -> P0.6, HP interrupter -> P0.7 (CPU pin 28 region), release
  switch -> P0.0, tractor switch -> P0.2, panel buttons -> P3.3-3.7 (pullup array RA3).
- Motor commons: CR CMN A/B <- P3.0 (TR1/TR6), LF CMN A/B <- P3.1 (TR4/TR5), +25 V / +5 V.
- Head thermistor: TH+ = 5 V, TH- -> 10k/cap node -> P4.3 (AN3).
