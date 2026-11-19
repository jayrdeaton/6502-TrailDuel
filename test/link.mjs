// Two emulators joined by a script that carries serial bytes between them,
// dropping and damaging some on the way when a test asks it to.
//   node test/link.mjs                every test
//   node test/link.mjs basic noisy    just those
// Screenshots go to test/out. CART names another cartridge.
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Emulator, JOY, checks } from './emulator.mjs'

const CART = process.env.CART ?? join(dirname(fileURLToPath(import.meta.url)), '../TrailDuel.crt')
let a, b
const { eq, done } = checks()

// Zero page (src/zeropage.inc)
const TITLE = 0, PLAYING = 1, GAMEOVER = 3, LINKING = 5, LINK = 2
const read = async m => {
  const [state, mode] = await m.mem(0x3a, 2)
  const p = await m.mem(0x40, 10)
  const [result, c1, c2] = await m.mem(0x61, 3)
  const [on, up, bad] = await m.mem(0x8b, 3)
  const [seat] = await m.mem(0x91)
  const [lt, , peer] = await m.mem(0x99, 3)
  const [stall] = await m.mem(0x9f)
  const [h1, h2] = await m.mem(0xbb, 2)                     // bit 8 of each x
  return { state, mode, p1: [p[0] + h1 * 256, p[1], p[2], p[4]], p2: [p[5] + h2 * 256, p[6], p[7], p[9]], result, colors: [c1, c2], on, up, bad, seat, lt, peer, stall }
}
// The round as both machines should agree on it
const round = s => ({ state: s.state, result: s.result, p1: s.p1, p2: s.p2, lt: s.lt, colors: s.colors })

let wire = true, lose = 0, flip = 0, carried = 0, seed = 4242
const rand = n => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) >> 8) % n
// A machine that isn't linked has its serial port quiet, and on the board what
// arrives then is lost. The emulator would hold it and feed it in later, so the
// cable drops it here.
const carry = async (from, to) => {
  let bytes = await from.out()
  if (!bytes.length) return
  carried += bytes.length
  if (!wire || !(await to.mem(0x8b))[0]) return
  if (lose) bytes = bytes.filter(() => rand(1000) >= lose)
  if (flip) bytes = bytes.map(v => (rand(1000) < flip ? v ^ (1 << rand(8)) : v))
  if (bytes.length) await to.send(bytes)
}
const step = async (n = 8000) => {
  await Promise.all([a.run(n), b.run(n)])
  await carry(a, b)
  await carry(b, a)
}
const steps = async cycles => {
  for (let t = 0; t < cycles; t += 8000) await step()
}
const until = async (test, limit = 30000000) => {
  for (let t = 0; t < limit; t += 8000) {
    if (await test()) return true
    await step()
  }
  return false
}
// The emulator's side b is the BIOS's joystick 1.
const press = async (m, bits) => {
  await m.stick(bits, 'b')
  await steps(160000)
  await m.stick(0, 'b')
  await steps(160000)
}
const fire = m => press(m, JOY.a)
// The frame round the arena: palette entry 8, black, or red while waiting
const RED = 0xf55, BLACK = 0
const frameColor = async m => (await m.rpc('video.palette')).entries[8]

// Two machines switched on, until both are on the title. Each test gets a new
// pair: the emulator holds serial bytes across a reset, so a pair reset after
// one test would still be getting the last one's.
const boot = async () => {
  if (a) await Promise.all([a.stop(), b.stop()])
  ;[a, b] = await Promise.all([Emulator.start({ cart: CART, name: 'A' }), Emulator.start({ cart: CART, name: 'B' })])
  wire = true
  lose = flip = 0
  await Promise.all([a.run(3000000), b.run(3000000)])
  const frames = async m => { const [lo, hi] = await m.mem(0xb1, 2); return lo + hi * 256 }
  await until(async () => (await frames(a)) > 30 && (await frames(b)) > 30, 20000000)
  await Promise.all([a.drain(), b.drain()])
}
// Both on LINK from the title, A on one, a moment, A on the other.
const connect = async (l = 0, f = 0) => {
  await boot()
  lose = l
  flip = f
  carried = 0
  for (const m of [a, b]) {
    await press(m, JOY.right)                                // the menu opens on MODE:
    await press(m, JOY.right)                                // right twice is LINK
  }
  await fire(a)
  await steps(300000)
  await fire(b)
  return until(async () => {
    const [x, y] = await Promise.all([read(a), read(b)])
    return x.state === PLAYING && y.state === PLAYING
  }, 10000000)
}
// Each machine's player turns now and then, at random, until the round ends.
const DIRS = [JOY.up, JOY.down, JOY.left, JOY.right]
const play = async (limit = 60000000) => {
  for (let t = 0; t < limit; t += 8000) {
    const [x, y] = await Promise.all([read(a), read(b)])
    if (x.state !== PLAYING && y.state !== PLAYING) {
      // A round's state turns to game over before its message is drawn, and
      // the tick count moves on after that: let both finish drawing.
      await steps(1500000)
      return Promise.all([read(a), read(b)])
    }
    for (const m of [a, b]) {
      if (!rand(25)) await m.stick(DIRS[rand(4)], 'b')
      else if (!rand(4)) await m.stick(0, 'b')
    }
    await step()
  }
  return [await read(a), await read(b)]
}
const same = async (name, x, y) => {
  eq(`${name}: both machines end the round the same`, round(x), round(y))
  eq(`${name}: neither found a disagreement`, [x.bad, y.bad, x.state, y.state], [0, 0, GAMEOVER, GAMEOVER])
}

const tests = {
  async title() {
    await boot()
    await press(a, JOY.right)
    await press(a, JOY.right)
    eq('right twice on MODE is LINK', (await read(a)).mode, LINK)
    await a.shot('link-title')
    await press(a, JOY.right)
    eq('and once more back to one player', (await read(a)).mode, 0)
    await press(a, JOY.left)
    eq('left goes back to LINK', (await read(a)).mode, LINK)
    await fire(a)
    const s = await read(a)
    eq('A looks for the other machine', [s.state, s.on, s.up], [LINKING, 1, 0])
    await steps(2000000)
    eq('and keeps looking while it is alone', (await read(a)).state, LINKING)
    await a.shot('linking')
    await fire(a)
    await until(async () => (await read(a)).state === TITLE, 3000000)
    const t = await read(a)
    eq('A gives up and goes back to the title', [t.state, t.on, t.mode], [TITLE, 0, LINK])
  },

  async basic() {
    eq('both machines start the round', await connect(), true)
    // One may be a tick ahead of the other: look when they're at the same one.
    await until(async () => (await read(a)).lt === (await read(b)).lt, 400000)
    const [x, y] = await Promise.all([read(a), read(b)])
    eq('one takes each seat', [x.seat + y.seat, x.seat !== y.seat], [1, true])
    eq('both have the same round', round(x), round(y))
    eq('the same color twice: the second seat moves on one', x.colors, [4, 5])
    await steps(1500000)
    await a.shot('link-a')
    await b.shot('link-b')
    const [u, v] = await play()
    await same('a clean cable', u, v)
    eq('one machine says it won and the other lost, or both crashed', u.result === 3 || u.result - 1 === u.seat || u.result - 1 === v.seat, true)
    await steps(1500000)
    await a.shot('link-over-a')
    await b.shot('link-over-b')
    console.log(`round of ${u.lt} ticks, ${carried} bytes`)
  },

  async steer() {
    // A person on each side: the first machine's player goes up at once, the
    // other's down, and each machine shows both.
    await connect()
    const [x] = await Promise.all([read(a), read(b)])
    const up = x.seat === 0 ? 'p1' : 'p2'
    await a.stick(JOY.up, 'b')
    await b.stick(JOY.down, 'b')
    await steps(1000000)
    await a.stick(0, 'b')
    await b.stick(0, 'b')
    const [s, t] = await Promise.all([read(a), read(b)])
    eq('each machine steers its own rider, and both see both', [s[up][2], s[up === 'p1' ? 'p2' : 'p1'][2]], [0, 1])
    eq('the other machine agrees', [t[up][2], t[up === 'p1' ? 'p2' : 'p1'][2]], [0, 1])
  },

  // Machine A on FAST, B on SLOW: both play the round at the first seat's.
  async speed() {
    await boot()
    await press(a, JOY.down)                                // SPEED
    await press(a, JOY.right)                               // NORMAL to FAST
    await press(b, JOY.down)
    await press(b, JOY.left)                                // NORMAL to SLOW
    for (const m of [a, b]) {
      await press(m, JOY.up)                                // MODE
      await press(m, JOY.right)
      await press(m, JOY.right)                             // LINK
    }
    await fire(a)
    await steps(300000)
    await fire(b)
    eq('both start', await until(async () => (await read(a)).state === PLAYING && (await read(b)).state === PLAYING, 10000000), true)
    const speeds = await Promise.all([a, b].map(async m => (await m.mem(0xc3))[0]))
    const first = (await read(a)).seat === 0 ? 2 : 0
    eq('both play at the first seat\'s speed', speeds, [first, first])
    const lt0 = (await read(a)).lt
    await steps(1000000)
    const ticks = ((await read(a)).lt - lt0 + 256) % 256
    eq(`and keep it up: ${ticks} ticks a second`, Math.abs(ticks - (first === 2 ? 60 : 20)) <= 3, true)
  },

  async noisy() {
    for (const [l, f] of [[20, 5], [40, 10]]) {
      const up = await connect(l, f)
      eq(`link up, ${l / 10}% lost, ${f / 10}% damaged`, up, true)
      const [u, v] = await play()
      await same(`${l / 10}% lost, ${f / 10}% damaged`, u, v)
      console.log(`round of ${u.lt} ticks, ${carried} bytes`)
      lose = flip = 0
    }
  },

  async cable() {
    await connect()
    await steps(1000000)
    wire = false
    const [x0] = await Promise.all([read(a), read(b)])
    await steps(1500000)
    const [x, y] = await Promise.all([read(a), read(b)])
    eq('cable out: both wait', [x.lt - x0.lt <= 4, x.stall >= 30, y.stall >= 30], [true, true, true])
    eq('with the frame round the arena red', await frameColor(a), RED)
    await a.shot('waiting')
    wire = true
    await steps(1000000)
    const [s, t] = await Promise.all([read(a), read(b)])
    eq('cable back: the round goes on', [s.lt > x.lt, s.stall, t.stall, await frameColor(a)], [true, 0, 0, BLACK])
    const [u, v] = await play()
    await same('after the cable came back', u, v)
  },

  // A round long enough for the 8-bit tick count to wrap, on a noisy cable:
  // each player rides a path round the edge of their half, turning at set
  // places, until both reach the bottom or top wall.
  async long() {
    await connect(Number(process.env.LOSE ?? 40), Number(process.env.FLIP ?? 10))
    const ways = {
      0: [[r => r[0] >= 90, JOY.up, 0], [r => r[1] <= 24, JOY.right, 3], [r => r[0] >= 130, JOY.down, 1]],
      1: [[r => r[0] <= 230, JOY.down, 1], [r => r[1] >= 214, JOY.right, 3], [r => r[0] >= 290, JOY.up, 0]]
    }
    const plan = await Promise.all([a, b].map(async m => ({ m, seat: (await read(m)).seat, step: 0 })))
    let wraps = 0, last = 0, t = 0
    for (; t < 80000000; t += 8000) {
      const [x, y] = await Promise.all([read(a), read(b)])
      if (x.state !== PLAYING && y.state !== PLAYING) break
      if (x.lt < last) wraps++
      last = x.lt
      for (const [p, s] of [[plan[0], x], [plan[1], y]]) {
        const way = ways[p.seat][p.step]
        const rider = p.seat === 0 ? s.p1 : s.p2
        if (way && way[0](rider)) await p.m.stick(way[1], 'b')
        if (way && rider[2] === way[2]) {
          await p.m.stick(0, 'b')
          p.step++
        }
      }
      await step()
    }
    await steps(1500000)
    const [u, v] = await Promise.all([read(a), read(b)])
    await same('a long round', u, v)
    eq('it ran past 256 ticks', wraps >= 1, true)
    const ticks = wraps * 256 + u.lt
    console.log(`round of ${ticks} ticks in ${(t / 1e6).toFixed(1)} s, ${(ticks / (t / 1e6)).toFixed(1)} a second, ${carried} bytes`)
    await a.shot('link-long')
  },

  async rematch() {
    await connect()
    let [u, v] = await play()
    await same('the first round', u, v)
    await steps(1500000)
    await fire(a)
    await steps(300000)
    await fire(b)
    const again = await until(async () => {
      const [x, y] = await Promise.all([read(a), read(b)])
      return x.state === PLAYING && y.state === PLAYING
    }, 10000000)
    eq('A after a round starts another', again, true)
    eq('from the start', (await read(a)).lt < 30, true);
    [u, v] = await play()
    await same('the second round', u, v)
  },

  // Not in the usual run: ROUNDS rounds back to back by rematch, on a noisy cable.
  async soak() {
    const rounds = Number(process.env.ROUNDS ?? 20)
    await connect(Number(process.env.LOSE ?? 40), Number(process.env.FLIP ?? 10))
    let ok = 0, ticks = 0
    for (let r = 0; r < rounds; r++) {
      const [u, v] = await play()
      const fine = JSON.stringify(round(u)) === JSON.stringify(round(v)) && !u.bad && !v.bad && u.state === GAMEOVER
      if (fine) ok++
      else console.log('round', r, JSON.stringify(round(u)), JSON.stringify(round(v)), u.bad, v.bad)
      ticks += u.lt
      await fire(a)
      await steps(200000 + rand(600000))
      await fire(b)
      const again = await until(async () => {
        const [x, y] = await Promise.all([read(a), read(b)])
        return x.state === PLAYING && y.state === PLAYING
      }, 20000000)
      if (!again) {
        console.log('no rematch after round', r, JSON.stringify(await read(a)), JSON.stringify(await read(b)))
        break
      }
    }
    eq(`${rounds} rounds by rematch, ${lose / 10}% lost, ${flip / 10}% damaged, all end the same`, ok, rounds)
    console.log(`${ticks} ticks, ${carried} bytes`)
  },

  async quit() {
    await connect()
    wire = false
    await steps(1500000)
    await fire(a)
    await until(async () => (await read(a)).state === TITLE, 3000000)
    const s = await read(a)
    eq('A while waiting gives up', [s.state, s.on, await frameColor(a)], [TITLE, 0, BLACK])
    wire = true
  },

  async alone() {
    await boot()
    await b.send([...Buffer.from('WWWWSSSS AAAA')])
    await steps(1000000)
    const s = await read(b)
    eq('a machine not linking ignores what comes in', [s.state, s.mode], [TITLE, 0])
  }
}

try {
  const names = process.argv.slice(2)
  for (const t of names.length ? names : Object.keys(tests).filter(t => t !== 'soak')) {
    if (!tests[t]) throw new Error(`no test ${t}: ${Object.keys(tests).join(' ')}`)
    await tests[t]()
  }
} finally {
  done()
  if (a) await Promise.all([a.stop(), b.stop()])
}
