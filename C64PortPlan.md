# Commodore 64 port plan

Goal: run Sakarin villapaitapeli on a **stock C64** (PAL or NTSC, 6581 or
8580 SID, 1541 drive, joystick/keyboard) with **no extra hardware**. The
voice clips are the joke, so they must play as real samples through the
regular SID chip.

The port reuses what the raylib port already settled (`CportPlan.md`):
the 7-stage state machine, the 320 × 200 layout table and the animation
timings. Only the platform layer changes.

Everything is **one PRG** loaded once. No disk access during play.

---

## 1. Toolchain (everything is already installed here except one packer)

| Tool | Use | Status |
|------|-----|--------|
| `cc65` / `cl65` | C compiler + assembler + linker for the 6502 | installed |
| `x64sc` (VICE) | cycle-exact emulator for testing (6581 and 8580 models) | installed |
| `c1541` (VICE) | build the `.d64` disk image | comes with VICE |
| `ffmpeg`, `magick`, `python3` (stdlib only) | offline asset conversion | installed |
| `salvador` (ZX02 packer) or `exomizer` | LZ compression of the graphics | **to install** (optional, see §4) |

---

## 2. Memory budget: the core constraint

64 KB RAM, but the ROMs, I/O, zero page and the screen take their share.
Memory map:

| Range | Size | Use |
|-------|------|-----|
| `$0000–$07FF` | 2 KB | zero page, stack, KERNAL vars, default screen (unused) |
| `$0801–$BFFF` | **45.0 KB** | program code + all compressed assets (BASIC ROM banked out) |
| `$C000–$C3E7` | 1 KB | VIC screen matrix = hires colours (VIC bank 3) |
| `$C400–$CFFF` | 3 KB | C stack, BSS, player variables, spare |
| `$D000–$DFFF` | 4 KB RAM under I/O | temporary background buffer for the sweater animation (§5) |
| `$E000–$FF3F` | 8 KB | hires bitmap (RAM under KERNAL: the CPU writes there, the VIC reads it) |

Vectors at `$FFFA+` aren't touched, so the KERNAL can stay switched in.
The NMI hook goes through `$0318`.

**Budget for `$0801–$BFFF` (46,079 bytes):**

| Item | Estimate |
|------|----------|
| cc65 runtime + game logic in C | ~3.5 KB |
| asm: NMI sample player, SID setup/detect, decompressor | ~0.7 KB |
| graphics: 7 stage screens + sweater overlay + colour maps (ZX02) | ~9.5 KB |
| sound: 6 clips, **4-bit @ 5 kHz** | ~28.7 KB |
| **Total** | **~42.4 KB → ~2.6 KB headroom** |

If the graphics use simple RLE instead of ZX02, they take about 12 KB and
headroom drops to around 0. That's why an LZ packer is recommended.

---

## 3. Sound: reducing the assets

### 3.1 Starting point (measured from `assets/sounds/*.wav`)

| Clip | Stage | Length |
|------|-------|--------|
| `sakarin_villapaitapeli` | intro | 2.25 s |
| `pue_sakarille_villapaita` | question | 2.27 s |
| `hmm` | selectedNo | 1.23 s |
| `hihihi_kutittaa` | tickling | 2.46 s |
| `havisit_pelin` | gameLost | 1.46 s |
| `voitit_pelin` | gameWon | 2.59 s |
| **Total** | | **12.27 s = 98 KB** at the current 8 kHz/8-bit |

98 KB is more than the whole machine, so it has to shrink by about 3.5×.

### 3.2 Reduction steps, in order of "free" to "costly"

1. **Trim leading/trailing silence** (−40 dB threshold, edges only, never
   inside a phrase): 12.27 s → **11.74 s (−4 %)**. Free.
   *Careful:* ffmpeg `silenceremove` with `stop_periods` cuts at the first
   pause *inside* the clip (tested: it chopped the intro clip to 0.13 s).
   Trim with `silenceremove,areverse,silenceremove,areverse` instead.
2. **Compress dynamics + normalize** (`acompressor`, then peak normalize)
   before quantizing. This costs no bytes but matters a lot: 4 bits has
   only 16 levels, so quiet syllables have to be pushed up into them.
3. **4-bit samples, 2 per byte**: −50 %. This is also exactly what the
   SID volume register can output (§3.3), so nothing is wasted.
4. **Lower the sample rate** with a low-pass at ~0.45 × rate first:
   speech stays intelligible down to ~4 kHz ("walkie-talkie" quality,
   which suits the humour).
5. *(Optional)* **Speed up 10 %** with `atempo=1.1` (pitch stays the same):
   another −8 %. The voices sound a bit hurried.

### 3.3 Size table (after edge trim, 11.74 s total)

| Rate | 8-bit raw | **4-bit packed** | 2-bit ADPCM | Quality |
|------|-----------|------------------|-------------|---------|
| 8000 Hz | 91.7 KB | 45.9 KB ✗ | 22.9 KB ✓ | ADPCM: bandwidth OK, audible noise |
| 6000 Hz | 68.8 KB | 34.4 KB ✗ (no room for gfx) | 17.2 KB ✓ | |
| 5512 Hz | 63.2 KB | 31.6 KB ~ (fits with 0 KB margin) | 15.8 KB | |
| **5000 Hz** | 57.3 KB | **28.7 KB ✓ recommended** | 14.3 KB | clear speech, muffled |
| 4000 Hz | 45.9 KB | 22.9 KB ✓ | 11.5 KB | muffled, still intelligible |
| 5512 Hz + atempo 1.1 | | 28.9 KB ✓ | | |

**Recommendation: 4-bit linear PCM @ 5 kHz (28.7 KB).** It is the simplest
player (no decoding), fits the budget, and keeps 2.2 kHz of bandwidth.
**Plan B**, if listening tests show the 5 kHz version is too dull: a 2-bit
ADPCM @ 8 kHz (22.9 KB). Its decoder in the NMI is about 25 cycles more,
and it actually *saves* 6 KB.

Preview WAVs (4-bit and 2-bit ADPCM simulations at 4000/5512/6000/8000 Hz)
were rendered for listening in
`/tmp/claude-1000/-home-henri-kokeiluita-villapaita/79c82283-b0ba-46a0-aeb2-7f947ef862e3/scratchpad/pre/`.
They don't model the SID's analogue colouring, so do the final check in
`x64sc`.

### 3.4 Playback on a stock SID

- **Method:** the classic `$D418` (master volume) digi. Each sample nibble
  is written to the low 4 bits of `$D418`.
- **Timer:** CIA2 timer A → NMI at the sample rate. At 5 kHz that is every
  197 cycles on PAL (985,248 Hz) and every 205 cycles on NTSC (1,022,727 Hz).
  Detect PAL/NTSC at start.
- **NMI handler:** about 35–45 cycles. It reads a byte, outputs the high
  or low nibble on alternate calls, advances the pointer, and sets a `done`
  flag at the end. That is ~22 % CPU at 5 kHz, which is fine because the
  game is idle while a clip plays.
- **6581 vs 8580:** on the 6581, `$D418` writes are loud because of its DC
  offset. On the 8580 they are almost silent unless boosted: set the
  voices to a constant DC level (test bit + pulse waveform, sustain $F) so
  the volume register has something to scale. Detect the SID model at
  start-up with the usual `$D41B` voice-3 oscillator test, and apply the
  boost only on the 8580.
- **Clicks:** ramp `$D418` from 0 to the midpoint (8) before a clip and back
  after it. Keep the filter-mode bits (upper nibble) at 0.
- **Badlines and sprites** steal cycles, which causes ±40-cycle jitter.
  At 5 kHz that can't be heard. Don't use sprites while sound plays.
- **"One channel" rule** from the original: `go(stage)` stops the NMI
  timer, sets the new clip pointer/end and restarts the timer. The stage
  auto-advance condition "sound ended" becomes `player_done != 0`.

---

## 4. Graphics: reducing the assets

### 4.1 Mode

- **Hires bitmap, 320 × 200, VIC bank 3.** The art is black line drawing
  on white (most source PNGs are literally 2-colour), so hires fits
  perfectly. Each 8 × 8 cell gets an ink/paper pair from the screen
  matrix: black on white by default, black on **light green** for sweater
  cells, black on **light blue** for button cells.
- The 320 × 200 positions in `CportPlan.md` §3 are reused 1:1. The C64's
  320 × 200 shown at 4:3 is the same geometry as the DOS target.

### 4.2 Pre-compose whole stage screens offline

Instead of storing 13 separate images and blitting them at unaligned
positions (slow, and needs shifting code), compose one 320 × 200 screen
per stage offline, with all images and buttons already in place and
clipped:

| Screen | Contents |
|--------|----------|
| intro | title + Aloita |
| question | question + En + Joo |
| selectedNo | Sakari hmm |
| selectedYes | surprised Sakari (sweater is drawn at runtime) |
| tickling | Sakari in sweater + "hihihi kutittaa" |
| gameLost | Hävisit + Uudelleen |
| gameWon | Voitit + Uudelleen |
| sweater | 211 × 101 overlay, cell-aligned bitmap + mask |

### 4.3 Measured sizes (1-bit, C64 cell byte order)

| | Raw | RLE | LZ (zlib/lzma as a stand-in for ZX02/exomizer) |
|--|-----|-----|-----|
| All 13 images, cropped | 50.3 KB | 11.6 KB | **9.0 KB** |
| 7 full screens if stored raw | 7 × 9 KB = 63 KB ✗ | | |

- Expect the 7 composed screens to come to about **9 KB LZ** in total
  (the buttons are the only duplicates). The sweater overlay with its mask
  is about 0.5 KB.
- **Colour maps:** 1000 bytes per screen raw, but there are only a few
  runs (white background, a green block, blue button cells). RLE brings
  that to ~50–150 bytes per screen, ~0.7 KB total.
- **Decompression:** ZX02 (6502 decoder ~150 bytes) straight into
  `$E000`. It takes ~0.2–0.3 s per screen, and runs **before** the stage's
  clip starts (screen blanked via `$D011` bit 4 while unpacking, so there's
  no garbage).

### 4.4 Conversion details

- Threshold to 1-bit **after** flattening on white. Light fills
  (`#b5c0ff`, `#8cc67b`, `#7489fe`) must become *paper* (0), and their
  cells get a colour from the colour map. The fill colour comes from a
  majority vote per cell over the source RGB.
- Palette mapping: `#8cc67b` → C64 light green (13). `#7489fe`/`#b5c0ff`
  → light blue (14). Black/white stay as they are.
- Cells with two non-black colours can't be shown in hires. They take the
  majority colour (only a few pixels at sweater/button edges).

---

## 5. Animations on the C64

- **Tickling shake** (`{0,0} {3,-3} {-1,2}`, one step per ~0.117 s =
  6 PAL frames): use the **VIC hardware fine scroll**, with no redrawing.
  Set the base to `XSCROLL=1, YSCROLL=3`, so the offsets become x ∈ 0..4
  and y ∈ 0..5. Switch to 38-column/24-row mode during this stage so the
  edges don't flicker. Write the registers from a raster IRQ in the lower
  border to avoid badline glitches. *Simplification:* the whole screen
  shakes, including the "hihihi" text. In the original only Sakari shakes.
- **Sweater slide** (16 steps over 1.5 s, x = −185 → 45, y = 116):
  - Round each step's x to a multiple of 8 so the sweater is copied cell
    by cell, without bit-shifting.
  - On entering selectedYes, copy bitmap rows 14–24 (11 × 320 B = 3.5 KB)
    to the **RAM under I/O at `$D000`**. This stage is silent, so the NMI
    is off and banking `$01` is trivial.
  - For each step: restore the background cells from that buffer, then
    draw the sweater with AND-mask/OR-bitmap, and set the green colour
    cells.
- **Button feedback:** none needed (the original has none). Buttons are
  part of the screen.

---

## 6. Input

The original uses mouse or keys `1`/`2`. The C64 port:

- keys **1 / 2** (via `cbm_k_getin()` or a direct keyboard matrix scan);
- **joystick port 2:** up = 1st button, down = 2nd button, fire =
  the only button on screens that have one.
- A 1351 mouse is extra hardware, so it is left out of scope.

---

## 7. Code structure

```
c64/
  Makefile           # make → villapaita.prg + villapaita.d64
  c64.cfg            # custom ld65 config (memory map of §2)
  main.c             # stage table + loop (port of the raylib main.c)
  sid.s              # SID/PAL detect, 8580 boost, NMI 4-bit player
  gfx.s              # ZX02 decoder, colour-RLE unpacker, sweater blit
  assets.s           # .incbin of the generated binaries, with labels
  tools/
    c64_assets.py    # compose screens → bitmap+colour → pack; wav → nibbles
    build_assets.sh  # runs ffmpeg/magick, then c64_assets.py, then salvador
  build/             # generated *.bin (committed, like the raylib port's assets)
```

`main.c` keeps the data-driven design of the raylib port:

```c
typedef struct {
    const unsigned char *screen, *colors;   // packed stage screen
    const unsigned char *snd, *snd_end;     // NULL = silence
    unsigned char next, wait_frames;        // auto-advance; 0 = on sound end
    unsigned char btn_next[2];              // 0xFF = none
} Stage;

static void go(unsigned char s) {
    snd_stop();
    VIC.ctrl1 &= ~0x10;                     // blank
    unzx02(S[s].screen, (void*)0xE000);
    unrle_colors(S[s].colors, (void*)0xC000);
    VIC.ctrl1 |= 0x10;
    if (S[s].snd) snd_play(S[s].snd, S[s].snd_end);
    cur = s; frames = 0;
}
```

The main loop waits for vsync (a raster IRQ counter), polls input, runs
the two animations and checks `wait_frames` or `snd_done`.

---

## 8. Milestones

1. **Sound proof-of-concept** (the risky part first): a tiny asm PRG that
   plays one 4-bit 5 kHz clip from NMI. Test in `x64sc` with both
   `-sidenginemodel 6581` and `8580`. Decide between 5 kHz PCM and 2-bit
   ADPCM by ear.
2. **Asset pipeline:** `c64_assets.py` produces 7 screens + sweater +
   6 clips. Print a size report and fail the build if the total exceeds
   the §2 budget.
3. **Static slideshow:** cc65 `main.c` with the stage table, decompression,
   keys 1/2 and sound. The game is playable at this point.
4. **Animations:** fine-scroll shake and sweater slide.
5. **Polish:** joystick input, PAL/NTSC timer constants, click-free volume
   ramps, an `exomizer sfx` crunched PRG for a shorter load time, and a
   `.d64` via `c1541`.
6. **Real hardware check,** if available (6581 and 8580 sound very
   different with `$D418` digis).

---

## 9. Risks and fallbacks

| Risk | Fallback |
|------|----------|
| 4-bit 5 kHz sounds too dull | 2-bit ADPCM @ 8 kHz (saves 6 KB) |
| Out of memory | Use `$C400–$CFFF` (3 KB) and `$D000–$DFFF` for clip data (NMI banks `$01`, +10 cycles); or atempo 1.1 (−2.6 KB); or 4.5 kHz |
| 8580 digis too quiet | Stronger boost (all 3 voices DC), or the "Mahoney" 8-bit `$D418` technique (table-based, works on both SIDs, more work) |
| Load time from 1541 (~45 KB ≈ 1.5–2 min with the stock loader) | Crunch the PRG with exomizer. The audio barely compresses, so expect ~35–38 KB on disk. Splitting loads per stage is possible, but this plan keeps everything in memory. |
| Source WAVs are already 8 kHz/8-bit (the original MP3s aren't in this directory) | Fine, because every target rate is ≤ 8 kHz. Use the MP3s if they turn up, for a cleaner low-pass. |
