# C + raylib port plan

Goal: the **smallest C program** that runs this game with graphics and
sound. That means one `main.c` (target ≈ 100–120 lines) built on raylib.
All the heavy lifting is done **offline** when the assets are preprocessed:

- images are pre-rendered at their final **320 × 200** size in an
  **8-colour** palette
- sounds are converted to **8 kHz, 8-bit mono** WAV (low-quality Sound
  Blaster voices)

The C code only loads files, draws textures 1:1 and plays sounds. It doesn't
scale images, convert formats or do any effects.

---

## 1. The game

A 7-stage state machine (`src/game.ts`, `index.html`, `src/style.css`):

| Stage       | Picture                                   | Sound              | Advance                        |
|-------------|-------------------------------------------|--------------------|--------------------------------|
| intro       | title + Aloita button                     | `sakarin_villapaitapeli` | click / key `1` → question |
| question    | question + En / Joo buttons               | `pue_sakarille_villapaita` | En (`1`) → selectedNo, Joo (`2`) → selectedYes |
| selectedNo  | Sakari thinking                           | `hmm`              | sound ends → gameLost          |
| selectedYes | surprised Sakari + sweater slides in      | *(silence)*        | 1.5 s → tickling               |
| tickling    | Sakari in sweater, shaking + text         | `hihihi_kutittaa`  | sound ends → gameWon           |
| gameLost    | "Hävisit pelin" + Uudelleen button        | `havisit_pelin`    | click / key `1` → intro        |
| gameWon     | "Voitit pelin" + Uudelleen button         | `voitit_pelin`     | click / key `1` → intro        |

Audio rule: there is **one sound channel**. Entering a stage stops whatever
is playing, then starts that stage's sound, if it has one.

---

## 2. Asset preprocessing

Output goes into `cport/assets/`. The PNGs and WAVs are committed, so
building the game itself needs no tools besides a C compiler and raylib.

- **Images:** `rsvg-convert` rasterizes each SVG straight to 320 × 200 scale
  (x × 320/550, y × 200/400). `aloita` also includes the CSS `scale(1.93)`.
  Then `magick` remaps the colours to a fixed 8-colour palette (no
  dithering) and makes the alpha 1-bit.
- **Palette:** the 5 colours the SVGs actually use (`#000000 #ffffff
  #7489fe #b5c0ff #8cc67b`), plus 3 darker edge shades
  (`#808080 #3a4480 #46633e`).
- **Sounds:** `ffmpeg` converts each one to 8000 Hz, unsigned 8-bit, mono
  WAV. A low-pass filter at 3.6 kHz is applied first to avoid harsh aliasing.
- **Names:** the `ä` in file names becomes `a`, so all names are ASCII.

`cport/tools/convert_assets.sh` (run from `cport/`):

```sh
#!/bin/sh
set -e
SRC=../src/assets
DST=assets
mkdir -p "$DST/images" "$DST/sounds"

magick xc:'#000000' xc:'#ffffff' xc:'#7489fe' xc:'#b5c0ff' \
       xc:'#8cc67b' xc:'#808080' xc:'#3a4480' xc:'#46633e' +append pal.png

for f in "$SRC"/images/*.svg; do
  name=$(basename "$f" .svg | sed 's/ä/a/g')
  zx=0.581818; zy=0.5
  [ "$name" = aloita ] && { zx=1.122909; zy=0.965; }   # includes scale(1.93)
  out="$DST/images/$name.png"
  rsvg-convert --x-zoom "$zx" --y-zoom "$zy" "$f" -o "$out"
  # -remap drops alpha, so remap RGB separately and copy the thresholded alpha back
  magick "$out" \
         \( -clone 0 -alpha extract -threshold 50% \) \
         \( -clone 0 -alpha off -dither None -remap pal.png \) \
         -delete 0 +swap -compose CopyOpacity -composite "$out"
done

for f in "$SRC"/sounds/*.mp3; do
  name=$(basename "$f" .mp3 | sed 's/ä/a/g')
  ffmpeg -loglevel error -y -i "$f" -af lowpass=f=3600 \
         -ar 8000 -ac 1 -acodec pcm_u8 "$DST/sounds/$name.wav"
done
rm -f pal.png
```

(Tested on this machine: the image pipeline gives ≤ 8 colours with correct
transparency, and the WAVs come out as `pcm_u8, 8000 Hz, mono`.)

---

## 3. Layout in 320 × 200

The positions come from the CSS. Three quirks matter:

- The stage-wide `img { left; top }` rule also moves the images *inside*
  buttons and wrapper divs, so those offsets add up.
- `scale(1.93)` on Aloita grows from the image's center.
- Every value is scaled by x × 0.5818 and y × 0.5, then rounded.

| Stage       | Image                  | x   | y   |
|-------------|------------------------|-----|-----|
| intro       | `sakarin_villapaitapeli` | -5 | 7  |
| intro       | `aloita` (button `1`)  | 151 | 87  |
| question    | `pue_sakarille_villapaita` | 27 | 8 |
| question    | `en` (button `1`)      | 195 | 71  |
| question    | `joo` (button `2`)     | 196 | 136 |
| selectedNo  | `sakari_hmm`           | 47  | 4   |
| selectedYes | `sakari_yllattynyt`    | 55  | 5   |
| selectedYes | `villapaita`           | -185 → 45 | 116 |
| tickling    | `sakari_villapaidalla` | 55  | 13  |
| tickling    | `hihihi_kutittaa`      | 4   | 31  |
| gameLost    | `havisit_pelin`        | -5  | 13  |
| gameLost    | `uudelleen` (button `1`) | 134 | 154 |
| gameWon     | `voitit_pelin`         | -15 | 8   |
| gameWon     | `uudelleen` (button `1`) | 131 | 154 |

Button hit area = `{x, y, texture.width, texture.height}`.

**Animations** (`t` = seconds in the stage):

- **Sweater:** `x = -185 + (int)(229.8f * (int)(t / 1.5f * 16) / 16)`,
  clamped at step 16. This gives 16 discrete jumps (CSS `steps(16, end)`).
- **Shake:** offsets `{0,0} {3,-3} {-1,2}`, chosen by
  `(int)(fmodf(t, 0.35f) / 0.35f * 3)`. The CSS 100 % keyframe is never
  visible with `steps(1, end)`.

---

## 4. Display

No render texture and no letterboxing: just a fixed **960 × 720** window,
which is 320 × 200 shown at 4:3 like a DOS screen (x × 3, y × 3.6).

```c
InitWindow(960, 720, "Sakarin Villapaitapeli");
SetMouseScale(1/3.0f, 1/3.6f);          // mouse in 320x200 coordinates
...
BeginDrawing(); ClearBackground(WHITE);
rlPushMatrix(); rlScalef(3, 3.6f, 1);   // #include "rlgl.h"
    /* draw everything in 320x200 coordinates */
rlPopMatrix();
EndDrawing();
```

Textures use `TEXTURE_FILTER_POINT`, which is raylib's default, so no call
is needed. The window edges clip anything that is drawn off-screen.

---

## 5. Code design: one table + one loop

Describe each stage with **data**. The only code that differs per stage is
the two animations.

```c
enum { INTRO, QUESTION, SEL_NO, SEL_YES, TICKLING, LOST, WON };

typedef struct { int img, x, y, next; } Btn;  // button key = index + 1
typedef struct {
    int img, x, y;   // main picture
    int snd;         // -1 = silence
    Btn btn[2];      // img < 0 = unused
    int next;        // auto-advance target, -1 = none
    float wait;      // > 0: advance after this many seconds; 0: when sound ends
} Stage;

static const Stage S[] = {
 [INTRO]    = { I_TITLE, -5, 7,  W_INTRO, {{I_ALOITA,151,87,QUESTION},{-1}}, -1 },
 [QUESTION] = { I_QUEST, 27, 8,  W_QUEST, {{I_EN,195,71,SEL_NO},{I_JOO,196,136,SEL_YES}}, -1 },
 [SEL_NO]   = { I_HMM,   47, 4,  W_HMM,   {{-1},{-1}}, LOST },
 [SEL_YES]  = { I_SURPR, 55, 5,  -1,      {{-1},{-1}}, TICKLING, 1.5f },
 [TICKLING] = { I_SHIRT, 55, 13, W_HIHI,  {{-1},{-1}}, WON },
 [LOST]     = { I_LOST,  -5, 13, W_LOST,  {{I_RETRY,134,154,INTRO},{-1}}, -1 },
 [WON]      = { I_WON,  -15, 8,  W_WON,   {{I_RETRY,131,154,INTRO},{-1}}, -1 },
};
```

Assets are kept as two file-name arrays that match the `I_*` / `W_*` enums,
and loaded in one loop each (`LoadTexture`, `LoadSound`).

Main loop, in outline:

```c
static void Go(int s) {
    for (int i = 0; i < W_COUNT; i++) StopSound(snd[i]);
    if (S[s].snd >= 0) PlaySound(snd[S[s].snd]);
    cur = s; t = 0;
}

// per frame:
t += GetFrameTime();
const Stage *st = &S[cur];
Vector2 o = cur == TICKLING ? SHAKE[(int)(fmodf(t, .35f) / .35f * 3)] : (Vector2){0};
DrawTexture(tex[st->img], st->x + o.x, st->y + o.y, WHITE);
if (cur == SEL_YES)  DrawTexture(tex[I_SWEATER], SweaterX(t), 116, WHITE);
if (cur == TICKLING) DrawTexture(tex[I_HIHI], 4, 31, WHITE);

int next = -1;
for (int i = 0; i < 2; i++) {
    const Btn *b = &st->btn[i];
    if (b->img < 0) continue;
    DrawTexture(tex[b->img], b->x, b->y, WHITE);
    Rectangle r = { b->x, b->y, tex[b->img].width, tex[b->img].height };
    if ((IsMouseButtonPressed(0) && CheckCollisionPointRec(GetMousePosition(), r))
        || IsKeyPressed(KEY_ONE + i)) next = b->next;
}
if (st->next >= 0 && (st->wait > 0 ? t >= st->wait
                                    : !IsSoundPlaying(snd[st->snd]))) next = st->next;
// draw the whole frame first, then switch stages
if (next >= 0) Go(next);
```

Notes:

- `IsSoundPlaying` returns true right after `PlaySound`, so the
  "sound ended" check works from the first frame.
- `IsKeyPressed` (not `IsKeyDown`) means holding a key can't skip screens.
- For the smallest code, leave out: hover cursor, numpad keys, Enter/Space,
  window resizing, unloading on exit (the OS frees everything).
  `CloseAudioDevice()` and `CloseWindow()` are still called.

---

## 6. Build

```
cport/
├── Makefile
├── main.c
├── tools/convert_assets.sh
└── assets/images/*.png  assets/sounds/*.wav
```

```make
villapaitapeli: main.c
	cc -std=c99 -Os -Wall -o $@ $< $$(pkg-config --cflags --libs raylib) -lm

assets:
	sh tools/convert_assets.sh
```

raylib 6.0.0 is installed system-wide. Run the game from `cport/` so that
`assets/` resolves, or add `ChangeDirectory(GetApplicationDirectory())`.

---

## 7. Steps

1. Write and run `convert_assets.sh`, then commit `assets/`.
2. Write `main.c`: the enums, the file-name arrays, the stage table and the
   loop above.
3. Play through both paths and compare against the web version (`bun dev`).

## 8. Done when

- [ ] Both paths work, by mouse and by keys (intro `1`, question `1` = En /
      `2` = Joo, retry `1`), and both loop back to intro.
- [ ] Starting a stage cuts off the previous sound. selectedYes is silent
      for 1.5 s while the sweater jumps in 16 steps to x = 45.
- [ ] Tickling shakes and advances when the giggle ends. selectedNo
      advances when "hmm" ends.
- [ ] Graphics are 320 × 200 at 4:3 in ≤ 8 colours. Sounds are 8 kHz 8-bit mono.
- [ ] `main.c` stays around 100–120 lines.
