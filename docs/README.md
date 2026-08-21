# NX-1020 - Documentation

Reverse-engineering reference documentation for the Star NX-1020, reconstructed from the two
ROM dumps and the schematic and cross-checked against the technical manual. Final outputs are
in `../deliverables/`; the firmware disassemblies and tooling are in `../work/`.

**Path convention:** file references inside these docs are relative to the **project root** -
`work/<x>` is the tooling folder and `deliverables/<x>` is a final output. Bare glyph-sheet
filenames (e.g. `FONT_courier.png`) refer to the sheets in `deliverables/`.

## Contents
- **THEORY_OF_OPERATION.md** - the full machine model: power-on/reset → receiving data →
  command interpretation → line building → font lookup → head fire → carriage → paper feed →
  error/protection paths, plus the two memory spaces (§0a). The place to start.
- **ROM_MAP.md** - full ROM1 / ROM2 memory map: banks, font regions, the 8-byte metrics tables
  (width + `rec[2]` bearing + `rec[4]` descender), and the coverage audit. (Interactive
  companion: `deliverables/ROM_MAP.html`.)
- **ESC_COMMANDS.md** - the decoded C0 control-code and ESC command tables (STD/Epson and IBM
  emulations) with their firmware handler addresses.
- **PORT_MAP.md** - the M50734 special-function registers, per-port bit assignments, gate-array
  registers, schematic-confirmed external nets, and the front-panel lamp error codes emitted by
  the six fatal traps.
