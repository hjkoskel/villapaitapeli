# Sakarin villapaitapeli

A small, silly Finnish game: put a sweater (*villapaita*) on Sakari. Say
*Joo* and he giggles because it tickles; say *En* and you lose. The voice
clips are the heart of the joke.

This repository has two ports of the game, both written in C:

- a **PC version** built on [raylib](https://www.raylib.com/) (`main.c`)
- a **Commodore 64 version** that runs on a stock C64 (`c64/`). The voice
  clips play as samples through the regular SID chip, with no extra hardware.

Watch a playthrough: https://youtu.be/5VG0eHE3YjE

Code repository: https://github.com/hjkoskel/villapaitapeli

## Credits

**Sakarin villapaitapeli** was created by **Mikko Alenius**. The game idea,
drawings and voice clips are his. This repository only ports the game to C
and the Commodore 64.

## Playing on a Commodore 64

### Where to find the .d64 file

The ready-made disk image is in the repository:

```
c64/villapaita.d64
```

On GitHub, open the `c64` folder at
https://github.com/hjkoskel/villapaitapeli, click `villapaita.d64` and
choose **Download raw file**. To build it yourself, see
[Building the C64 version](#building-the-c64-version) below.

### Running it

- **Emulator (VICE):** run `x64sc villapaita.d64`, or drag the file onto the
  VICE window. It starts automatically.
- **Real C64:** write the image to a floppy, or copy it to an SD2IEC /
  Pi1541 / Kung Fu Flash or similar, then type:

  ```
  LOAD"VILLAPAITA",8
  RUN
  ```

  The program is about 42 KB, so loading with a stock 1541 takes a while.

Works on PAL and NTSC machines, with either a 6581 or 8580 SID. Samples are
quieter on the 8580.

### Controls

The bottom row of each screen shows which keys work there.

| Button | Keys / joystick (port 2) |
|--------|--------------------------|
| Aloita, Uudelleen | `1`, `SPACE`, `RETURN`, fire |
| En | `1`, `E`, `N`, joystick up |
| Joo | `2`, `J`, `Y`, joystick down |

## Building the C64 version

You need [cc65](https://cc65.github.io/). The generated assets in
`c64/build/` are part of the repository, so cc65 alone is enough:

```sh
cd c64
make            # -> villapaita.prg and villapaita.d64
make run        # start in VICE
```

Regenerating the assets from `assets/` (`make assets`) also needs
`python3`, ImageMagick (`magick`), `ffmpeg`, the
[zx02](https://github.com/dmsc/zx02) packer and VICE's character ROM.
See [c64/README.md](c64/README.md) for the memory map and file overview,
and [C64PortPlan.md](C64PortPlan.md) for how the graphics and sound were
squeezed into 64 KB.

## Building the PC (raylib) version

Needs a C compiler and raylib (found with `pkg-config`):

```sh
make
./villapaitapeli
```

Click the buttons with the mouse, or press `1` / `2`. See
[CportPlan.md](CportPlan.md) for the design.

## Repository layout

| Path | Contents |
|------|----------|
| `main.c`, `Makefile` | raylib PC version |
| `assets/` | 320×200 images and 8 kHz voice clips used by both ports |
| `tools/convert_assets.sh` | converts the original web-game assets |
| `c64/` | Commodore 64 version |
| `CportPlan.md`, `C64PortPlan.md` | design notes for the two ports |
