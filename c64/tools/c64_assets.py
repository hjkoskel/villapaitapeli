#!/usr/bin/env python3
"""Convert the 320x200 PNG/WAV assets of the raylib port into C64 data.

Output (in build/):
  scr_<stage>.bm.zx02   hires bitmap, 8000 bytes, ZX02 packed
  scr_<stage>.col.zx02  screen matrix (fg<<4 | bg per 8x8 cell), ZX02 packed
  sweater.zx02          sweater overlay for the sliding animation
  snd_<name>.bin        4-bit samples, 2 per byte (high nibble first)
  assets.inc            constants for the assembler
Uses only the Python stdlib + external `magick`, `ffmpeg` and `zx02`.
"""
import os
import subprocess
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "../assets"
OUT = sys.argv[2] if len(sys.argv) > 2 else "build"
RATE = 5000

# C64 colours
BLACK, WHITE, LGREEN, LBLUE = 0, 1, 13, 14

# source palette -> class (C64 colour). Dark edge shades count as black ink.
PALETTE = [
    ((0x00, 0x00, 0x00), BLACK),
    ((0x80, 0x80, 0x80), BLACK),
    ((0x3a, 0x44, 0x80), BLACK),
    ((0x46, 0x63, 0x3e), BLACK),
    ((0xff, 0xff, 0xff), WHITE),
    ((0x8c, 0xc6, 0x7b), LGREEN),
    ((0x74, 0x89, 0xfe), LBLUE),
    ((0xb5, 0xc0, 0xff), LBLUE),
]

# stage screens: list of (image, x, y), positions from CportPlan.md section 3
STAGES = [
    ("intro",    [("sakarin_villapaitapeli", -5, 7), ("aloita", 151, 87)]),
    ("question", [("pue_sakarille_villapaita", 27, 8), ("en", 195, 71), ("joo", 196, 136)]),
    ("selno",    [("sakari_hmm", 47, 4)]),
    ("selyes",   [("sakari_yllattynyt", 55, 5)]),
    ("tickling", [("sakari_villapaidalla", 55, 13), ("hihihi_kutittaa", 4, 31)]),
    ("lost",     [("havisit_pelin", -5, 13), ("uudelleen", 134, 154)]),
    ("won",      [("voitit_pelin", -15, 8), ("uudelleen", 131, 154)]),
]
# key guide drawn on the bottom text row (row 24) with the C64 font
GUIDES = {
    "intro":    "1/SPACE/RETURN/FIRE: ALOITA",
    "question": "1/E/N/UP: EN   2/J/Y/DOWN: JOO",
    "lost":     "1/SPACE/RETURN/FIRE: UUDELLEEN",
    "won":      "1/SPACE/RETURN/FIRE: UUDELLEEN",
}
CHARGEN = os.environ.get("CHARGEN", "/usr/share/vice/C64/chargen-901225-01.bin")

SOUNDS = ["sakarin_villapaitapeli", "pue_sakarille_villapaita", "hmm",
          "hihihi_kutittaa", "havisit_pelin", "voitit_pelin"]

# sweater band: cell rows 14..24, sweater top at y=116 -> 4 px into the band
SW_ROW0, SW_ROWS, SW_COLS, SW_YOFS = 14, 11, 27, 4


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, **kw).stdout


def load_png(name):
    """Returns (w, h, pixels) where a pixel is a C64 colour or None (transparent)."""
    path = os.path.join(SRC, "images", name + ".png")
    w, h = map(int, run(["magick", path, "-format", "%w %h", "info:"]).split())
    raw = run(["magick", path, "-depth", "8", "rgba:-"])
    px = []
    for i in range(w * h):
        r, g, b, a = raw[i * 4:i * 4 + 4]
        if a < 128:
            px.append(None)
            continue
        best = min(PALETTE, key=lambda p: (p[0][0] - r) ** 2 + (p[0][1] - g) ** 2 + (p[0][2] - b) ** 2)
        px.append(best[1])
    return w, h, px


def compose(items, images):
    canvas = [WHITE] * (320 * 200)
    for name, x0, y0 in items:
        w, h, px = images[name]
        for y in range(h):
            sy = y0 + y
            if not 0 <= sy < 200:
                continue
            for x in range(w):
                sx = x0 + x
                c = px[y * w + x]
                if c is not None and 0 <= sx < 320:
                    canvas[sy * 320 + sx] = c
    return canvas


def to_hires(canvas):
    """2 colours per 8x8 cell. Black is always the ink when present."""
    bm = bytearray(8000)
    scr = bytearray(1000)
    lost = 0
    for cy in range(25):
        for cx in range(40):
            cnt = {}
            for r in range(8):
                for b in range(8):
                    c = canvas[(cy * 8 + r) * 320 + cx * 8 + b]
                    cnt[c] = cnt.get(c, 0) + 1
            order = sorted(cnt, key=lambda c: -cnt[c])
            if BLACK in cnt:
                fg = BLACK
                others = [c for c in order if c != BLACK]
                bg = others[0] if others else WHITE
            elif len(order) >= 2:
                bg, fg = order[0], order[1]
            else:
                fg, bg = BLACK, order[0]
            lost += sum(n for c, n in cnt.items() if c not in (fg, bg))
            scr[cy * 40 + cx] = (fg << 4) | bg
            for r in range(8):
                v = 0
                for b in range(8):
                    if canvas[(cy * 8 + r) * 320 + cx * 8 + b] == fg:
                        v |= 0x80 >> b
                bm[cy * 320 + cx * 8 + r] = v
    return bm, scr, lost


def draw_guide(bm, scr, text, font):
    """Centre text on cell row 24, black on white, replacing those cells."""
    col0 = (40 - len(text)) // 2
    for i, ch in enumerate(text):
        if "A" <= ch <= "Z":
            code = ord(ch) - 64          # screen code
        else:
            code = ord(ch)               # space, digits, ':' and '/' match ASCII
        cx = col0 + i
        scr[24 * 40 + cx] = (BLACK << 4) | WHITE
        bm[24 * 320 + cx * 8:24 * 320 + cx * 8 + 8] = font[code * 8:code * 8 + 8]


def zx02(data, path):
    raw = path + ".raw"
    with open(raw, "wb") as f:
        f.write(data)
    run(["zx02", "-f", raw, path], stderr=subprocess.DEVNULL)
    os.remove(raw)
    return os.path.getsize(path)


def sweater(images):
    """Cell types (0 transparent, 1 opaque, 2 edge), colours, ink, masks."""
    w, h, px = images["villapaita"]
    T, C, ink, mask = bytearray(), bytearray(), bytearray(), bytearray()
    for cr in range(SW_ROWS):
        for cc in range(SW_COLS):
            ib, mb = bytearray(8), bytearray(8)
            green = 0
            for r in range(8):
                y = cr * 8 + r - SW_YOFS
                for b in range(8):
                    x = cc * 8 + b
                    if 0 <= y < h and x < w and px[y * w + x] is not None:
                        mb[r] |= 0x80 >> b
                        if px[y * w + x] == BLACK:
                            ib[r] |= 0x80 >> b
                        elif px[y * w + x] == LGREEN:
                            green += 1
            if not any(mb):
                t = 0
            elif all(m == 0xFF for m in mb):
                t = 1
            else:
                t = 2
            T.append(t)
            C.append((BLACK << 4 | LGREEN) if green >= 24 else 0)
            if t:
                ink += ib
            if t == 2:
                mask += mb
    return T, C, ink, mask


def sound(name):
    src = os.path.join(SRC, "sounds", name + ".wav")
    trim = "silenceremove=start_periods=1:start_threshold=-40dB"
    af = ",".join([trim, "areverse", trim, "areverse",
                   "acompressor=threshold=-20dB:ratio=4:attack=5:release=80:makeup=2",
                   "lowpass=f=%d" % (RATE * 45 // 100),
                   "afade=t=in:d=0.005", "areverse", "afade=t=in:d=0.01", "areverse"])
    pcm = run(["ffmpeg", "-loglevel", "error", "-i", src, "-af", af,
               "-ar", str(RATE), "-ac", "1", "-f", "s16le", "-"])
    x = [v - 65536 if v >= 32768 else v
         for v in (pcm[i] | pcm[i + 1] << 8 for i in range(0, len(pcm), 2))]
    dc = sum(x) / len(x)
    x = [v - dc for v in x]
    # 4 bits is only 16 levels: scale so the 99.5th percentile of the
    # amplitude reaches full scale and clip the rare peaks above it.
    ref = sorted(abs(v) for v in x)[int(len(x) * 0.995)] or 1
    gain = 7.5 / ref
    nib = [max(0, min(15, int(round(v * gain + 8)))) for v in x]
    pcm = x
    if len(nib) & 1:
        nib.append(8)
    return bytes((nib[i] << 4) | nib[i + 1] for i in range(0, len(nib), 2)), len(pcm)


def main():
    os.makedirs(OUT, exist_ok=True)
    names = {n for _, items in STAGES for n, _, _ in items} | {"villapaita"}
    images = {n: load_png(n) for n in sorted(names)}
    with open(CHARGEN, "rb") as f:
        font = f.read(2048)              # upper case / graphics set
    total = 0
    print("%-10s %6s %6s %6s" % ("screen", "bitmap", "colour", "lost"))
    for stage, items in STAGES:
        bm, scr, lost = to_hires(compose(items, images))
        if stage in GUIDES:
            draw_guide(bm, scr, GUIDES[stage], font)
        a = zx02(bytes(bm), os.path.join(OUT, "scr_%s.bm.zx02" % stage))
        b = zx02(bytes(scr), os.path.join(OUT, "scr_%s.col.zx02" % stage))
        total += a + b
        print("%-10s %6d %6d %6d px" % (stage, a, b, lost))

    T, C, ink, mask = sweater(images)
    blob = bytes(T + C + ink + mask)
    s = zx02(blob, os.path.join(OUT, "sweater.zx02"))
    total += s
    print("sweater    %6d packed, %d unpacked (%d opaque, %d edge cells)"
          % (s, len(blob), T.count(1), T.count(2)))
    gfx = total

    stot = 0
    for n in SOUNDS:
        data, samples = sound(n)
        with open(os.path.join(OUT, "snd_%s.bin" % n), "wb") as f:
            f.write(data)
        stot += len(data)
        print("snd %-26s %5.2f s %6d bytes" % (n, samples / RATE, len(data)))

    with open(os.path.join(OUT, "assets.inc"), "w") as f:
        f.write("; generated by tools/c64_assets.py\n")
        f.write("SW_SIZE = %d\n" % len(blob))
        f.write("SW_T    = 0\n")
        f.write("SW_C    = %d\n" % len(T))
        f.write("SW_INK  = %d\n" % (len(T) + len(C)))
        f.write("SW_MASK = %d\n" % (len(T) + len(C) + len(ink)))
        f.write("SW_ROWS = %d\nSW_COLS = %d\nSW_ROW0 = %d\n" % (SW_ROWS, SW_COLS, SW_ROW0))
        f.write("SND_RATE = %d\n" % RATE)
    print("graphics %d bytes, sound %d bytes, total %d bytes (%.1f KB)"
          % (gfx, stot, gfx + stot, (gfx + stot) / 1024))


if __name__ == "__main__":
    main()
