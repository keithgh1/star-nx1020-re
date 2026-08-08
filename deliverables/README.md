# NX-1020 - Deliverables

Final outputs from the Star NX-1020 font-ROM reverse-engineering. Narrative documentation is
in `../docs/`; the disassembly control file and ROM-exploration tool are in `../work/`.

## Interactive ROM map
- **ROM_MAP.html** - a self-contained, clickable map of ROM1 (128 KB) + ROM2 (32 KB): columns
  per ROM/bank, regions color-coded by category (firmware / system code / pointer & descriptor
  tables / font metrics tables / glyph bitmaps per font / text), with an offset-sorted contents
  sidebar and a detail panel. Font regions link to their glyph sheet. (Interactive companion to
  `../docs/ROM_MAP.md`; cross-links to FONT_CATALOG.html.)

## Font catalog
- **FONT_CATALOG.html** / **FONT_CATALOG.pdf** - self-contained catalog of the resident fonts:
  the 5 typefaces (Draft, Courier, Sanserif, Orator, Script) plus the additional 8-dot Draft
  pitch and extended-character sets, each with a full glyph sheet and metadata.

## Glyph sheets (full character sets, rendered by the one generic box-grid engine)
- **FONT_draft.png** - Draft, Pica (10 cpi, 9×11), 8-dot.
- **FONT_courier.png / FONT_sanserif.png / FONT_orator.png / FONT_script.png** - the four 16-dot NLQ faces.
- **SET_8dot_pica_132C1.png** - Pica Draft (bounded view; same data as FONT_draft).
- **SET_8dot_cond_13DE1.png** - Condensed Draft (~17 cpi, 7 columns wide).
- **SET_8dot_w9_12B91.png / SET_8dot_w9_14509.png** - two distinct 9-column Draft faces. **Identity
  undetermined** (one is plausibly Elite; deliberately not guessed). HS-Draft is *not* a separate
  stored face, so neither is HS-Draft.
- **SET_8dot_accent_13129.png** - accented upper-half companion (no alphabet of its own).
- **SET_8dot_boxgfx_13851.png** - box-graphics + upper-half companion (no alphabet; index-labeled).

