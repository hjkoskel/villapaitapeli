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
