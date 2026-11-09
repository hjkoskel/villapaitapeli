# Sakarin villapaitapeli for the Commodore 64 (cc65)
#   make          -> villapaita.prg + villapaita.d64
#   make assets   -> regenerate build/ from ../assets (needs magick, ffmpeg, zx02)
#   make run      -> start in VICE
#   make autotest -> villapaita-auto.prg, which plays itself through

CFLAGS = -t c64 -Oirs -C c64.cfg
SRCS   = main.c sys.s assets.s
ASSETS = build/assets.inc

all: villapaita.prg villapaita.d64

$(ASSETS): tools/c64_assets.py
	python3 -I tools/c64_assets.py ../assets build

assets:
	python3 -I tools/c64_assets.py ../assets build

villapaita.prg: $(SRCS) c64.cfg $(ASSETS)
	cl65 $(CFLAGS) -m villapaita.map -o $@ $(SRCS)
	@echo "PRG size: `stat -c %s $@` bytes (max 47105)"

villapaita-auto.prg: $(SRCS) c64.cfg $(ASSETS)
	cl65 $(CFLAGS) -DAUTOTEST -o $@ $(SRCS)

autotest: villapaita-auto.prg

villapaita.d64: villapaita.prg
	c1541 -format "villapaita,sv" d64 $@ -write $< villapaita >/dev/null

run: villapaita.prg
	x64sc -autostart villapaita.prg

clean:
	rm -f *.o villapaita.prg villapaita-auto.prg villapaita.d64 villapaita.map

.PHONY: all assets autotest run clean
