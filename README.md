6502-TrailDuel
==============

TrailDuel for the [AC6502 ACE](https://github.com/acwright/6502-ACE), a trail duel for one or two players: each rider leaves a trail behind them, and the last one riding wins. Play a friend on one machine or on two machines linked over their serial ports, or the CPU. It was called LightCycles until 2026-11-19.

It runs on an ACE with a [6502-PICOVDP](https://github.com/acwright/6502-PICOVDP) on BIOS 2.x, as a 128 KB Flash Cart, on the whole 320 x 240 screen: the arena is 304 x 208. Until 2026-11-19 it was a 32 KB cart for the TMS9918A on BIOS 1.x, whose bitmap mode the PICOVDP doesn't have; that build is in the history before then.

**[Play it in your browser](https://games.infinitetoken.com/6502/trailduel)**, running in A.C. Wright's emulator. The cartridge is on [itch.io](https://jayrdeaton.itch.io/trailduel) too.

## Playing it

Load `TrailDuel.crt` in the [AC6502 emulator](https://github.com/acwright/6502-EMULATOR)
(3.0 or newer) with the video card set to PICOVDP, or from a terminal:

```sh
6502 run --vdp picovdp --cart TrailDuel.crt
```

## Controls

Joystick primary, keyboard fallback. Player 1 defaults to joystick 1, with
WASD as a fallback; player 2 defaults to joystick 2, with the arrow keys
as a fallback. Whichever joystick is being touched wins outright each
poll; the keyboard only takes over when that player's joystick shows
nothing that poll (including when no GPIO card is fitted at all). This
matches the standard convention for two people sharing one keyboard: WASD
is the physical left-hand cluster, arrow keys are the physical right-hand
cluster, so the two players' hands don't collide.

- **Up/Down/Left/Right** (joystick 1) or **W/A/S/D** (keyboard): turn
  player 1's cycle
- **Up/Down/Left/Right** (joystick 2) or **arrow keys** (keyboard): turn
  player 2's cycle
- **A button** (either joystick) or **Space** or **Enter** (keyboard): on
  the title screen, starts the round; during play, pauses/resumes; after a
  round, returns to the title screen

A bike always advances a pixel every tick; turning only changes its heading,
and takes effect on the next tick, so unlike Pong's paddles there's no need
to hold a direction to keep moving: the last direction pressed sticks until
changed again. Turning straight back is ignored.

The title is a menu. Up/Down on either joystick (or W/S, or the up and down
arrows) moves the arrows from line to line, and Left/Right (or A/D, or the
left and right arrows) changes the line they're on:

- **MODE:** one player against the CPU (1P), two on one machine (2P), or two
  machines linked (LINK)
- **SPEED:** SLOW, NORMAL or FAST, 20, 30 or 60 pixels a second: 15, 10 or 5
  seconds to cross the arena
- **P1, P2:** each player's trail color, never the same as the other's

## Sound

The sounds of Trap, TrailDuel's version in DuelTastic, rebuilt for the SID's three
voices (`tools/build-sound.mjs`): a blip each time a person turns (the CPU turns
quietly), a chord as a round starts, a crash, then a rising sting when a person at
the machine wins, or a falling one for a draw or a lost round. The menu, pause and
linking blip too. Sound needs the machine's GPIO card as well as the sound card,
because a timer on it keeps the sounds in time.

## Playing over a cable

Join two ACEs' serial ports with a null-modem cable (each machine's transmit to
the other's receive, and ground to ground). Each player sets MODE to LINK,
picks a color on the P1 line and presses A; the round starts when both have,
with the two riders on whichever sides the machines settle between them (the
same color twice and the right-hand rider takes the next one), at the
left-hand rider's machine's speed. Each player
steers their own rider with either joystick or either key cluster, and each
screen shows both. A round ends with YOU WIN, YOU LOSE or DOUBLE CRASH; A then
looks for the other machine again, for another round. A cancels while linking.

The machines send each other each tick's turns, so they stay in step; a turn
shows about 50 ms later than on one machine, the time it takes to cross the
cable with room to spare. Damaged bytes are sent again. If one machine has to
wait for the other, the frame round the arena turns red, and A there gives up
and goes back to the title. If the machines ever
disagree about the round they stop and say OUT OF SYNC. There's no pause in a
linked round. Both machines need the same build of the cartridge (OTHER BUILD
otherwise).

## Building

Needs [cc65](https://cc65.github.io/) and [6502-Lib](https://github.com/jayrdeaton/6502-Lib)
beside this folder.

```sh
make          # builds TrailDuel.crt
make sound    # redraws src/sounddata.inc from tools/build-sound.mjs (needs node)
make test     # builds, then plays it headless in the emulator
```

`src/sounddata.inc` is committed, so `make` alone needs only cc65 and 6502-Lib.

Everything that touches the video card is in `src/vdp.asm`: the game draws
the arena with `PixelSetP1Trail`, `PixelSetP2Trail` and `PixelSetBorder` and
tests it with `PixelIsSet`, in screen pixels (x takes 9 bits), draws the title
and messages with `PixelSet`, `PixelClear` and the text routines in a
256 x 192 area centered on the screen, and moves the riders' head sprites, so
another machine can replace that file. The arena is 38 x 26 cells of the
PICOVDP's Full mode, each with a tile of its own across two layers at 2 bits a
pixel (a layer holds 511), so each pixel has its own color, with a copy in RAM
that the collision test reads. The serial port is in
`src/link.asm`, the SID and the interrupt handler in `src/sound.asm`, and the
joysticks and keyboard in `src/input.asm`, on 6502-Lib's input.

## Testing

`test/rules.mjs` plays the real cart through the emulator's debug port with
the joysticks and keyboard a person would use: the title's menu, the three
speeds, the turns, walls and trails, pause, the keys and a round against the
CPU. `test/link.mjs`
joins two emulators by a script that carries the serial bytes between them,
dropping and damaging some on the way, and checks that both machines play out
the same rounds: clean and noisy cables, a round past 256 ticks, both at the
first seat's speed, the cable pulled and put back, rematches and giving up. `node test/link.mjs soak` plays
20 rounds back to back over a noisy cable (`ROUNDS`, `LOSE` and `FLIP` change
that). `test/sound.mjs` plays each sound on the cart, runs the SID registers
it writes through the emulator's own SID code into `test/out/sound/*.wav`
(nothing is played aloud), sets each beside its Trap original for length,
loudness, brightness and notes, and checks which sounds a game asks for and
when.

All three need the AC6502 emulator 3.0 or newer: set `EMULATOR` to its command
line, or build a checkout at `~/Developer/.tooling/6502-EMULATOR` with
`npm run build:cli`. The sound test also loads that checkout's SID code
(`SID` names another) and compares against DuelTastic's sounds when it finds
them (`DUELTASTIC`). Single tests run by name, e.g. `node test/rules.mjs cut
walls`. Screenshots and sounds land in `test/out`.

See PLAN.md for the original plan.

## License

The code is released under the MIT License, see [LICENSE](LICENSE).

The game's name, logo, and icons, and the original artwork and audio in this repository, are not covered by that license and remain all rights reserved. If you fork it, please give your version its own name and look.
