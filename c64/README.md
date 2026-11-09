# Sakarin villapaitapeli – Commodore 64

A port for a stock C64 (PAL or NTSC, 6581 or 8580 SID, no extra hardware).
The voice clips play as 4-bit, 5 kHz samples through the SID volume register.
The whole game is one 42 KB PRG that is loaded once (see `../C64PortPlan.md`).

## Controls

| Screen | Keys / joystick (port 2) |
|--------|--------------------------|
| Aloita, Uudelleen | `1`, space, return, fire |
| En | `1`, `E`, `N`, joystick up |
| Joo | `2`, `J`, `Y`, joystick down |

## Build

Needs `cc65`. Regenerating the assets also needs `python3`, `magick`,
`ffmpeg` and `zx02`.

```sh
make            # villapaita.prg + villapaita.d64
make run        # start in VICE (x64sc)
make assets     # rebuild build/ from ../assets/{images,sounds}
make autotest   # villapaita-auto.prg plays both endings by itself
```

On a real C64: `LOAD"VILLAPAITA",8` then `RUN`.

## Files

| File | Contents |
|------|----------|
| `main.c` | stage table and main loop (same state machine as the raylib port) |
| `sys.s` | init/IRQ, ZX02 decompressor, NMI sample player, sweater blitter, input |
| `assets.s` | `.incbin` of the generated data |
| `c64.cfg` | linker config: program in `$0801–$BFFF` |
| `tools/c64_assets.py` | PNG → hires stage screens (ZX02), WAV → 4-bit samples |

## Memory map

| Range | Use |
|-------|-----|
| `$0801–$BFFF` | code, packed screens (~10 KB), samples (~29 KB), C stack |
| `$C000–$C3E7` | screen matrix (hires colours) |
| `$C400–$CFFF` | unpacked sweater overlay (selectedYes stage only) |
| `$D000–$DF77` | RAM under I/O: background saved behind the sweater |
| `$E000–$FF3F` | hires bitmap |
| `$FFFA–$FFFF` | NMI/IRQ vectors in RAM (`$01 = $35`, KERNAL banked out) |
