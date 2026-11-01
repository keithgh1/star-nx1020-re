#!/usr/bin/env python3
"""
NX1020 ROM exploration toolkit.

ROM roles (determined by analysis):
  ROM1 = nx1020_rom1.ic7       (128 KB) - font/data ROM
  ROM2 = nx1020_rom2_v3.2.ic6  (32 KB)  - M50734 firmware

CPU: Mitsubishi M50734 (740-family, 6502-derived). External memory mode.
  - Firmware ROM2 maps to 0x8000-0xFFFF (top-aligned).
  - RAM occupies the lower address range; interrupt vectors point into RAM
    (handlers are set up / copied at init).
  - Vectors live at 0xFFF4-0xFFFF.

Usage examples (requires Pillow):
  python romtool.py vectors
  python romtool.py autocorr 0x12000          # find cell stride in bytes
  python romtool.py overview                  # full-ROM1 texture map -> rom1_overview.png
  python romtool.py glyphs 0x12000 24 12 16   # render 24-byte cells as 12x16 column-major
  python romtool.py strip 0x12000 2           # column-major strip, 2 bytes/column
"""
import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ROM1 = os.path.join(ROOT, "nx1020_rom1.ic7")
ROM2 = os.path.join(ROOT, "nx1020_rom2_v3.2.ic6")

def load(p): return open(p, "rb").read()

def cmd_vectors(_args):
    b = load(ROM2)
    names = {0xfff4:'TX/CNTR/BRK',0xfff6:'HE/VE',0xfff8:'Timer1/2/3',
             0xfffa:'RI/INT1',0xfffc:'INT2',0xfffe:'RESET'}
    for v in sorted(names):
        off = v - 0x8000
        addr = b[off] | (b[off+1] << 8)
        print(f"{v:04X} -> {addr:04X}   {names[v]}")

def cmd_autocorr(args):
    start = int(args[0], 0)
    rom = ROM1 if len(args) < 2 or args[1] != "rom2" else ROM2
    b = load(rom)
    pc = bytes(bin(x).count("1") for x in range(256))
    ink = [pc[x] for x in b]
    win = 8192
    reg = ink[start:start+win]; n = len(reg); m = sum(reg)/n
    var = sum((x-m)**2 for x in reg) or 1
    def ac(L): return sum((reg[i]-m)*(reg[i+L]-m) for i in range(n-L))/var
    peaks = sorted(((round(ac(L),3), L) for L in range(4,129)), reverse=True)[:10]
    print(f"{rom} @ {start:#07x} top strides (corr, bytes):")
    for c, L in peaks: print(f"   stride {L:3d}  corr {c}")

def _render_columns(b, start, ncols, bpc, cols_per_band, scale, fname, msb=True):
    from PIL import Image
    Hb = bpc*8; bands = (ncols+cols_per_band-1)//cols_per_band
    img = Image.new("L", (cols_per_band, bands*(Hb+3)), 170); px = img.load()
    for c in range(ncols):
        band = c//cols_per_band; x = c % cols_per_band
        for k in range(bpc):
            by = b[start + c*bpc + k]
            for bit in range(8):
                v = (by>>(7-bit))&1 if msb else (by>>bit)&1
                px[x, band*(Hb+3)+k*8+bit] = 0 if v else 255
    img.resize((cols_per_band*scale, bands*(Hb+3)*scale)).save(fname)
    print("wrote", fname)

def cmd_strip(args):
    start = int(args[0], 0); bpc = int(args[1]) if len(args) > 1 else 2
    msb = (len(args) < 3 or args[2] != "lsb")
    _render_columns(load(ROM1), start, 90*8, bpc, 90, 5,
                    os.path.join(HERE, f"strip_{start:05x}_bpc{bpc}.png"), msb)

def cmd_glyphs(args):
    """glyphs <start> <cellbytes> <gw> <gh> [per_row] [bpc] [msb|lsb]"""
    from PIL import Image
    start = int(args[0], 0); cell = int(args[1]); gw = int(args[2]); gh = int(args[3])
    per_row = int(args[4]) if len(args) > 4 else 16
    bpc = int(args[5]) if len(args) > 5 else cell // gw
    msb = (len(args) < 7 or args[6] != "lsb")
    b = load(ROM1); n = 256; cols = cell // bpc; pad = 1
    rows = (n+per_row-1)//per_row
    img = Image.new("L", (per_row*(gw+pad), rows*(gh+pad)), 170); px = img.load()
    for g in range(n):
        base = start + g*cell; gx = (g % per_row)*(gw+pad); gy = (g//per_row)*(gh+pad)
        for col in range(cols):
            for kb in range(bpc):
                by = b[base + col*bpc + kb]
                for bit in range(8):
                    v = (by>>(7-bit))&1 if msb else (by>>bit)&1
                    xx, yy = col, kb*8+bit
                    if xx < gw and yy < gh: px[gx+xx, gy+yy] = 0 if v else 255
    out = os.path.join(HERE, f"glyphs_{start:05x}_{cell}_{gw}x{gh}.png")
    img.resize((per_row*(gw+pad)*4, rows*(gh+pad)*4)).save(out)
    print("wrote", out)

def cmd_overview(_args):
    from PIL import Image
    b = load(ROM1); W = 64; rows = len(b)//W
    img = Image.new("L", (W*8, rows), 255); px = img.load()
    for off, by in enumerate(b):
        r = off//W; c = (off % W)*8
        for bit in range(8):
            if (by>>(7-bit))&1: px[c+bit, r] = 0
    out = os.path.join(HERE, "rom1_overview.png"); img.save(out)
    print(f"wrote {out}  (512 x {rows}; each row=64 bytes, 64 rows=0x1000)")

CMDS = {k[4:]: v for k, v in list(globals().items()) if k.startswith("cmd_")}
if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        print("commands:", ", ".join(sorted(CMDS))); sys.exit(1)
    CMDS[sys.argv[1]](sys.argv[2:])
