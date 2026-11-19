TARGET = TrailDuel
CONFIG = 6502-128K

.PHONY: all build sound view run test clean

all: build

build: $(TARGET).crt

$(TARGET).crt: $(TARGET).asm $(CONFIG).cfg 6502-VDP.inc $(wildcard src/*) $(wildcard ../6502-Lib/core/* ../6502-Lib/include/*)
	cl65 -t none -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm

# The sound effects (src/sounddata.inc is committed, so make alone doesn't need node)
sound:
	node tools/build-sound.mjs

view:
	hexdump -C $(TARGET).crt

run: build
	6502 run --vdp picovdp --cart $(TARGET).crt

# Plays the cart headless in the emulator (see test/emulator.mjs for which one)
test: build
	node test/rules.mjs && node test/link.mjs && node test/sound.mjs

clean:
	rm -f $(TARGET).crt $(TARGET).lst
