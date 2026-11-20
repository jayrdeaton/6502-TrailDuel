**A trail duel for one or two players, for the AC6502 ACE.** Each rider leaves a trail behind them. Turn sharply, stay off every trail, and be the last one riding.

**[Play it in your browser at games.infinitetoken.com](https://games.infinitetoken.com/6502/trailduel)**, in A.C. Wright's AC6502 emulator. Download the cartridge below to run it on your own machine or in the emulator on your computer.

## Features

- One player against a CPU rider, two players on one machine, or two machines linked by a serial cable
- The whole 320 x 240 screen, with every pixel of every trail in its rider's color
- Three speeds, from a slow drift to a pixel every frame
- Seven trail colors for each player, with the title's underlines following your pick
- Sound on the SID: a blip for each turn, a chord as a round starts, the crash, and a sting for the winner
- Riders never stop: your last turn holds until you turn again
- Pause any time mid-round on one machine

## What You Need

- An AC6502 ACE with a 6502-PICOVDP on BIOS 2.x, and a 128 KB Flash Cart. Sound needs the SID and the GPIO card.
- Or the [AC6502 emulator](https://github.com/acwright/6502-EMULATOR), 3.0 or newer, with the video card set to PICOVDP. From a terminal: `6502 run --vdp picovdp --cart TrailDuel.crt`
- For link play, two machines with the same cartridge, their serial ports joined by a null-modem cable.

## Controls

- **Player 1:** W A S D, or joystick 1
- **Player 2:** the arrow keys, or joystick 2
- **Space, Enter, or A on either joystick:** start, pause and resume, and back to the title after a round
- **On the title screen:** up and down move between MODE, SPEED and each player's color, and left and right change the one you're on
- **Linked:** each player steers their own rider with either joystick or either set of keys

## More

Also for the AC6502: [HexFleet](https://jayrdeaton.itch.io/hexfleet), turn-based starship battles on a hex grid. More of our games are at [games.infinitetoken.com](https://games.infinitetoken.com).

## Credits

Made by [Jay Deaton](https://jaydeaton.com). The AC6502 computers and emulator are by [A.C. Wright](https://acwrightdesign.itch.io). The source code is on [GitHub](https://github.com/jayrdeaton/6502-TrailDuel), MIT licensed.
