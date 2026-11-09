villapaitapeli: main.c
	cc -std=c99 -Os -Wall -Wextra -o $@ $< $$(pkg-config --cflags --libs raylib) -lm

assets:
	sh tools/convert_assets.sh

clean:
	rm -f villapaitapeli

.PHONY: assets clean
