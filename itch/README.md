# itch.io page

The settings and text for TrailDuel's page on itch.io, https://jayrdeaton.itch.io/trailduel, made 2026-11-20 on Jay's own account and laid out like 6502-HexFleet's (its `itch/README.md`, the first of these). The page offers the cartridge as a download, and its description links to the version that plays in a browser at games.infinitetoken.com.

`description.md` is the page's Description. itch's editor is rich text: paste the description as HTML in its source view (the `<>` button), or copy it from a rendered preview. Pasting the raw Markdown shows the `#`s and `**`s.

## Settings

| Field | Value |
| --- | --- |
| Title | TrailDuel |
| Project URL | `jayrdeaton.itch.io/trailduel` |
| Short description or tagline | A trail duel for one or two players on the AC6502 ACE. Stay off every trail and be the last one riding. |
| Classification | Games |
| Kind of project | Downloadable |
| Release status | Released |
| Pricing | $0 or donate, suggesting $3 like HexFleet and Wizards Lab |
| Uploads | `TrailDuel.crt`, of type Other (a cartridge image, not a build for Windows, macOS, Linux or Android), with its own name as the display name and no platform boxes ticked |
| Description | `description.md` |
| Genre | Action |
| Tags | `6502`, `homebrew`, `retro`, `8-bit`, `arcade`, `local-multiplayer`, `versus`, `minimalist` (take itch's own spelling of each as it suggests them). Never `tron` or `light-cycle`: the game was LightCycles until 2026-11-19 and was renamed to keep Tron's name off it. |
| Generative AI disclosure | Left unanswered, as on HexFleet: it's optional for games. Never answer No: the code was written with Claude. |
| App store links | None |
| Custom noun | Blank (game) |
| Download & install instructions | See below |
| Community | Comments |
| Visibility | Public |
| Metadata tab | Average session a few minutes, English, Keyboard and Joystick, local multiplayer, 1 to 2 players |

## Download & install instructions

Pasted as HTML in the field's source view:

```html
<p>Play it in the <a href="https://github.com/acwright/6502-EMULATOR">AC6502 emulator</a>, 3.0 or newer, with the video card set to PICOVDP. Load TrailDuel.crt as a cartridge, or from a terminal:</p>
<p><code>6502 run --vdp picovdp --cart TrailDuel.crt</code></p>
<p>On a real ACE, it needs a 6502-PICOVDP on BIOS 2.x and a 128 KB Flash Cart. For link play, both machines need this same cartridge, their serial ports joined by a null-modem cable.</p>
<p>No emulator? Play it in your browser at <a href="https://games.infinitetoken.com/6502/trailduel">games.infinitetoken.com</a>.</p>
```

## Theme

The cart's own colors, read from its screenshots:

| Setting | Value |
| --- | --- |
| BG and BG 2 | `#000000`, the playfield's black |
| Text | `#dcdce6`, the game's white toned down for reading |
| Link | `#44eeee`, the cyan trail |
| Font | Lato, Large |
| Banner | `banner.png`: the title screen's TRAIL DUEL with magenta and cyan underlines, at 4x on transparency, 960 x 148, centered. It takes the place of the page's title. |
| Background | None |

## Images

- **Cover image:** `cover.png`, 630 x 500: the TRAIL DUEL title over two riders' zigzag trails closing in, inside the arena's blue border (`#7777ff`). Composed at 210 x 167 from emulator frames and scaled up 3x, less its last row of black.
- **Screenshots** (`screenshots/`, in upload order), each a 320 x 240 capture scaled up 3x with nearest-neighbor to 960 x 720:
  1. `1-title.png`: the title's menu set to 2P at normal speed, with player 1 on magenta and player 2 on cyan
  2. `2-duel.png`: a two-player round across the whole screen, both riders zigzagging toward each other
  3. `3-cpu.png`: a one-player round against the CPU rider, about to turn into its trail
  4. `4-result.png`: PLAYER 2 WINS over the trails
- **Retaking them:** play the cart headless through its test harness (`test/emulator.mjs`, which starts the emulator with its debug server on the PICOVDP), steering with `emu.stick` and reading the riders' positions from zero page as `test/rules.mjs` does, and save frames with the `screen.png` call. Scale them up with ffmpeg's nearest-neighbor filter (`scale=960:720:flags=neighbor`). The banner is the title's TRAIL DUEL at 4x, placed at 244, 40.

## Keeping it in step

When the cartridge is rebuilt, upload the new `TrailDuel.crt` here and move the cart's pinned commit in Games-Web's `src/constants/site.ts` at the same time, so the download and the browser version are the same build.
