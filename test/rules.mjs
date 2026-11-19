// TrailDuel's rules, played through the real cart in a headless emulator with the
// joysticks and keyboard a person would use.
//   node test/rules.mjs              every test
//   node test/rules.mjs straight cut  just those
// CART names another cartridge and VDP another video card (VDP=tms9918a ran the
// TMS9918A cart these numbers were first taken from). Screenshots go to test/out.
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Emulator, JOY, checks } from './emulator.mjs'

const CART = process.env.CART ?? join(dirname(fileURLToPath(import.meta.url)), '../TrailDuel.crt')
const emu = await Emulator.start({ cart: CART, vdp: process.env.VDP ?? 'picovdp' })
const { mem, run, shot } = emu
const { eq, done } = checks()

// The emulator's side b is the stick on VIA port B, which the BIOS reads as joystick 1.
const J1 = 'b', J2 = 'a'

// Zero page (src/zeropage.inc)
const TITLE = 0, PLAYING = 1, GAMEOVER = 3, PAUSED = 4
const UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3
const read = async () => {
  const [state, mode] = await mem(0x3a, 2)
  const p = await mem(0x40, 10)
  const [result, c1, c2] = await mem(0x61, 3)
  const [h1, h2] = await mem(0xbb, 2)                       // bit 8 of each x
  const [row, , , speed] = await mem(0xc0, 4)
  const rider = (i, h) => ({ x: p[i] + h * 256, y: p[i + 1], dir: p[i + 2], alive: p[i + 4] })
  return { state, mode, p1: rider(0, h1), p2: rider(5, h2), result, colors: [c1, c2], row, speed }
}
const SLOW = 0, NORMAL = 1, FAST = 2

const boot = async () => {
  await emu.reset()
  await run(3000000)
}
// A press long enough for the game to see, then let go.
const press = async (bits, side = J1) => {
  await emu.stick(bits, side)
  await run(200000)
  await emu.stick(0, side)
  await run(200000)
}
const key = async code => {
  await emu.rpc('input.key', { code })
  await run(200000)
  await emu.rpc('input.key', { code, down: false })
  await run(200000)
}
// Runs until `test` holds, a few thousand cycles at a time (a tick is many more).
const until = async (test, limit = 60000000) => {
  for (let t = 0; t < limit; t += 4000) {
    const s = await read()
    if (await test(s)) return s
    await run(4000)
  }
  throw new Error('waited too long: ' + JSON.stringify(await read()))
}
// Holds side's stick in a direction until the rider has turned, then lets go.
const steer = async (side, bits, dir) => {
  await emu.stick(bits, side)
  const s = await until(s => (side === J1 ? s.p1 : s.p2).dir === dir, 2000000)
  await emu.stick(0, side)
  return s
}
const over = () => until(s => s.state === GAMEOVER)
// Starting a round or going back to the title redraws the screen, which takes a while.
const playing = () => until(s => s.state === PLAYING, 3000000)
const onTitle = () => until(s => s.state === TITLE, 3000000)
// A two-player round, started from the title: the menu opens on MODE, and right
// goes from one player to two.
const twoPlayer = async () => {
  await boot()
  await press(JOY.right)
  await press(JOY.a)
  return playing()
}
const pos = r => [r.x, r.y]

const tests = {
  async title() {
    await boot()
    const s = await read()
    eq('it boots to the title: one player, normal speed, blue against yellow, on MODE', [s.state, s.mode, s.speed, s.colors, s.row], [TITLE, 0, NORMAL, [4, 1], 0])
    await shot('title')
  },

  async menu() {
    await boot()
    await press(JOY.right)
    eq('right on MODE picks two players', (await read()).mode, 1)
    await press(JOY.right, J2)
    await press(JOY.right, J2)
    eq('either stick, and round past LINK to one player', (await read()).mode, 0)
    await press(JOY.left)
    eq('left goes back to LINK', (await read()).mode, 2)
    await press(JOY.down)
    await press(JOY.right)
    eq('down to SPEED, right to fast', [(await read()).row, (await read()).speed], [1, FAST])
    await press(JOY.right)
    eq('and round to slow', (await read()).speed, SLOW)
    await press(JOY.down)
    await press(JOY.right)
    await press(JOY.down, J2)
    await press(JOY.left)
    eq('each player\'s color on its own line', (await read()).colors, [5, 0])
    await press(JOY.up)
    await press(JOY.left)
    for (let i = 0; i < 4; i++) await press(JOY.right)
    eq('a color the other player has is skipped (4, 5, 6, past 0 to 1, 2)', (await read()).colors, [2, 0])
    await press(JOY.up)
    await press(JOY.up)
    await press(JOY.up)
    eq('up past the top goes round to the bottom', (await read()).row, 3)
    await shot('title-picked')
  },

  async speeds() {
    // One player riding straight on: how far in a second (a frame is 16,683 cycles)
    const rate = async speed => {
      await boot()
      await press(JOY.down)
      for (let i = 0; i < (speed - NORMAL + 3) % 3; i++) await press(JOY.right)
      await press(JOY.up)
      await press(JOY.a)
      const s = await playing()
      await run(1000000)
      const t = await read()
      return t.p1.x - s.p1.x
    }
    eq('slow, normal and fast ride about 20, 30 and 60 pixels a second', (await Promise.all([await rate(SLOW), await rate(NORMAL), await rate(FAST)])).map(d => Math.round(d / 10) * 10), [20, 30, 60])
  },

  async straight() {
    const s = await twoPlayer()
    eq('a round starts with the riders facing each other', [s.state, pos(s.p1), s.p1.dir, pos(s.p2), s.p2.dir], [PLAYING, [84, 120], RIGHT, [235, 120], LEFT])
    await until(s => s.p1.x >= 120)
    await shot('round')
    const e = await over()
    eq('riding straight, each hits the other\'s trail at once', [e.result, pos(e.p1), pos(e.p2), e.p1.alive, e.p2.alive], [3, [159, 120], [160, 120], 0, 0])
    await run(1500000)
    await shot('double-crash')
  },

  async cut() {
    await twoPlayer()
    await until(s => s.p1.x === 150)
    await steer(J1, JOY.up, UP)
    const e = await over()
    eq('the second rider runs into the first one\'s trail', [e.result, pos(e.p2), e.p1.alive, e.p2.alive], [1, [151, 120], 1, 0])
    eq('while the first rides on up', [e.p1.x, e.p1.y], [150, 102])
    await run(1500000)
    await shot('player1-wins')
  },

  async walls() {
    await twoPlayer()
    await until(s => s.p1.x === 90)
    await steer(J1, JOY.up, UP)
    await until(s => s.p2.x === 150)
    await steer(J2, JOY.down, DOWN)
    const e = await over()
    eq('the first to reach the border loses', [e.result, pos(e.p1), pos(e.p2), e.p1.alive, e.p2.alive], [2, [90, 17], [150, 144], 0, 1])
  },

  // The TMS9918A cart held a turn onto a vertical heading until the rider
  // reached an 8-pixel column whenever the other trail was in that column's
  // bytes, so here player 1 rode on into player 2's trail. Every pixel has its
  // own color on the PICOVDP, and a turn takes effect at once.
  async beside() {
    await twoPlayer()
    await until(s => s.p2.x === 180)
    await steer(J2, JOY.down, DOWN)
    await until(s => s.p2.y === 124)
    await steer(J2, JOY.left, LEFT)
    await until(s => s.p1.x === 178)
    await steer(J1, JOY.up, UP)
    await run(1000000)
    const s = await read()
    eq('a turn right beside the other trail happens at once', [s.state, s.p1.alive, s.p1.x, s.p1.dir, s.p1.y < 120], [PLAYING, 1, 178, UP, true])
  },

  async reverse() {
    await twoPlayer()
    await emu.stick(JOY.left, J1)
    await run(600000)
    await emu.stick(0, J1)
    const s = await read()
    eq('turning straight back is ignored', [s.p1.dir, s.p1.y, s.p1.x > 84], [RIGHT, 120, true])
  },

  async turns() {
    await twoPlayer()
    const path = [[JOY.down, DOWN], [JOY.left, LEFT], [JOY.up, UP], [JOY.right, RIGHT]]
    for (const [bits, dir] of path) {
      const s = await read()
      await until(t => t.p1.x !== s.p1.x || t.p1.y !== s.p1.y)
      await until(t => Math.abs(t.p1.x - s.p1.x) + Math.abs(t.p1.y - s.p1.y) >= 6)
      await steer(J1, bits, dir)
    }
    const s = await read()
    eq('a box: down, left, up, right', [s.p1.alive, s.p1.dir], [1, RIGHT])
    const e = await over()
    eq('and back into its own trail', [e.result, e.p1.alive], [2, 0])
  },

  async pause() {
    await twoPlayer()
    await run(1000000)
    await press(JOY.a)
    const a = await read()
    await run(1500000)
    const b = await read()
    eq('A pauses the round', [a.state, pos(b.p1), pos(b.p2)], [PAUSED, pos(a.p1), pos(a.p2)])
    await shot('paused')
    await press(JOY.a, J2)
    await run(500000)
    const c = await read()
    await shot('resumed')
    eq('and either stick resumes it', [c.state, c.p1.x > b.p1.x, c.p2.x < b.p2.x], [PLAYING, true, true])
  },

  async back() {
    await twoPlayer()
    await over()
    await run(1500000)
    await press(JOY.a)
    const s = await onTitle()
    eq('after a round, A goes back to the title, still on two players', [s.state, s.mode], [TITLE, 1])
  },

  async keys() {
    await boot()
    await key('KeyD')
    eq('D picks two players', (await read()).mode, 1)
    await key('KeyS')
    await key('ArrowUp')
    eq('S and the up arrow move between the lines', (await read()).row, 0)
    await key('Space')
    eq('space starts', (await playing()).state, PLAYING)
    await key('KeyS')
    await key('ArrowUp')
    const s = await read()
    eq('S turns the first rider and the up arrow the second', [s.p1.dir, s.p2.dir], [DOWN, UP])
    // Chrin would echo each key through Chrout, which brings the Kernal's text screen up
    eq('and the game keeps its own screen (Full, not the text console)', (await emu.rpc('video.info')).mode.vmode, 4)
    await shot('keys')
  },

  async cpu() {
    await boot()
    await press(JOY.a)
    const s = await playing()
    eq('one player starts against the CPU', [s.state, s.mode], [PLAYING, 0])
    await run(6000000)
    await shot('cpu')
    const e = await over()
    eq('riding straight on, you run into the CPU\'s trail', [e.result, pos(e.p1), e.p2.alive], [2, [210, 120], 1])
    await run(1500000)
    await shot('player2-wins')
  }
}

try {
  const names = process.argv.slice(2)
  for (const t of names.length ? names : Object.keys(tests)) {
    if (!tests[t]) throw new Error(`no test ${t}: ${Object.keys(tests).join(' ')}`)
    await tests[t]()
  }
} finally {
  done()
  await emu.stop()
}
