// The sounds, heard nowhere: each effect is played on the cart, the SID's registers
// are read after every sound tick, and they're run through the emulator's own SID
// code into test/out/sound/<name>.wav. Each is set beside its Trap original from
// DuelTastic (length, brightness, loudness, notes), and the game is played to check
// which sounds it asks for and when.
//   node test/sound.mjs
// DUELTASTIC names the DuelTastic checkout (default ~/Developer/DuelTastic).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Emulator, JOY, OUT, checks } from './emulator.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const CART = process.env.CART ?? join(here, '../TrailDuel.crt')
const APP = join(process.env.DUELTASTIC ?? join(homedir(), 'Developer/DuelTastic'), 'assets/sounds')
const SID = process.env.SID ?? join(homedir(), 'Developer/.tooling/6502-EMULATOR/out/core/IO/Sound.js')
const { Sound } = createRequire(import.meta.url)(SID)
const SFX = Object.fromEntries([...readFileSync(join(here, '../src/sounddata.inc'), 'utf8').matchAll(/^SFX_(\w+) = (\d+)/gm)].map(m => [m[1], Number(m[2])]))
const DIR = join(OUT, 'sound')
mkdirSync(DIR, { recursive: true })

const emu = await Emulator.start({ cart: CART })
const { mem, poke, run } = emu
const { eq, done } = checks()

// The driver's memory (src/zeropage.inc)
const S_REG = 0xa00, S_RTG = 0xa19, S_Q = 0xa20, S_QH = 0xa28, S_BUSY = 0xa2a, S_ON = 0xa2b, S_TICKS = 0xa2c, SF_ID = 0xa30
const ticks = async () => { const [lo, hi] = await mem(S_TICKS, 2); return lo + hi * 256 }
// Not while a tick is under way: it might take the request after its count has moved,
// and play its first frame before a capture starts.
const request = async fx => {
  for (let g = 0; (await mem(S_BUSY))[0] && g < 100; g++) await run(100)
  const [h] = await mem(S_QH)
  await poke(S_Q + h, fx)
  await poke(S_QH, (h + 1) & 7)
}

// The registers after each of the next `frames` ticks. The tick count moves as a
// tick starts, so this waits for the tick to finish before reading what it wrote.
const capture = async frames => {
  const out = []
  let t = await ticks(), lost = 0
  while (out.length < frames) {
    await run(16000)
    let now = await ticks()
    for (let g = 0; now === t && g < 40; g++) {
      await run(200)
      now = await ticks()
    }
    for (let g = 0; (await mem(S_BUSY))[0] && g < 100; g++) await run(100)
    lost += Math.max(0, now - t - 1)
    t = now
    out.push({ regs: await mem(S_REG, 25), rtg: await mem(S_RTG, 3) })
  }
  return { frames: out, lost }
}
// Through the emulator's SID, a 60th of a second a tick
const render = ({ frames }) => {
  const sid = new Sound(), chunks = []
  sid.pushSamples = s => chunks.push(Float32Array.from(s))
  sid.reset(true)
  let rtg = [0, 0, 0]
  frames.forEach((f, n) => {
    for (let v = 0; v < 3; v++) {
      if (n && f.rtg[v] !== rtg[v]) {
        sid.write(v * 7 + 4, f.regs[v * 7 + 4] & 0xfe)
        for (let c = 0; c < 60; c++) sid.tick(1000000)
      }
    }
    rtg = f.rtg
    f.regs.forEach((v, r) => sid.write(r, v))
    for (let c = 0; c < 16667; c++) sid.tick(1000000)
  })
  sid.flushSampleBuffer?.()
  const s = new Float32Array(chunks.reduce((a, c) => a + c.length, 0))
  let o = 0
  for (const c of chunks) { s.set(c, o); o += c.length }
  return s
}

const readWav = file => { const b = readFileSync(file); let p = 12, rate = 44100, data; while (p < b.length) { const id = b.toString('latin1', p, p + 4), len = b.readUInt32LE(p + 4); if (id === 'fmt ') rate = b.readUInt32LE(p + 12); if (id === 'data') { data = new Float32Array(len / 2); for (let i = 0; i < data.length; i++) data[i] = b.readInt16LE(p + 8 + i * 2) / 32768 } p += 8 + len + (len & 1) } return { s: data, rate } }
const writeWav = (file, s) => { const d = Buffer.alloc(44 + s.length * 2); d.write('RIFF', 0); d.writeUInt32LE(36 + s.length * 2, 4); d.write('WAVEfmt ', 8); d.writeUInt32LE(16, 16); d.writeUInt16LE(1, 20); d.writeUInt16LE(1, 22); d.writeUInt32LE(44100, 24); d.writeUInt32LE(88200, 28); d.writeUInt16LE(2, 32); d.writeUInt16LE(16, 34); d.write('data', 36); d.writeUInt32LE(s.length * 2, 40); s.forEach((v, i) => d.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), 44 + i * 2)); writeFileSync(file, d) }
const fft = (re, im) => { const n = re.length; for (let i = 1, j = 0; i < n; i++) { let b = n >> 1; for (; j & b; b >>= 1) j ^= b; j ^= b; if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]] } } for (let l = 2; l <= n; l <<= 1) { const a = -2 * Math.PI / l; for (let i = 0; i < n; i += l) for (let k = 0; k < l / 2; k++) { const c = Math.cos(a * k), s = Math.sin(a * k), x = re[i + k + l / 2] * c - im[i + k + l / 2] * s, y = re[i + k + l / 2] * s + im[i + k + l / 2] * c; re[i + k + l / 2] = re[i + k] - x; im[i + k + l / 2] = im[i + k] - y; re[i + k] += x; im[i + k] += y } } }
const spectrum = (s, rate, at, size = 8192) => { const p = Math.round(at * rate), re = new Float64Array(size), im = new Float64Array(size); for (let i = 0; i < size && p + i < s.length; i++) re[i] = s[p + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / size)); fft(re, im); return { mag: Array.from({ length: size / 2 }, (_, i) => re[i] * re[i] + im[i] * im[i]), hz: rate / size } }
const rms = s => Math.sqrt(s.reduce((a, v) => a + v * v, 0) / Math.max(1, s.length))
const db = v => (v > 0 ? 20 * Math.log10(v) : -120)
const NOTES = 'C C# D D# E F F# G G# A A# B'.split(' ')
const note = f => { const m = Math.round(12 * Math.log2(f / 440)) + 69; return NOTES[((m % 12) + 12) % 12] + (Math.floor(m / 12) - 1) }
// How long it lasts, how loud, how bright, and the notes in it at time `at`
const features = (s, rate) => {
  let peak = 0
  for (const v of s) peak = Math.max(peak, Math.abs(v))
  const win = Math.round(rate * 0.02), env = []
  for (let i = 0; i + win <= s.length; i += win) env.push(rms(s.subarray(i, i + win)))
  const top = Math.max(...env, 1e-9)
  let last = 0
  env.forEach((e, i) => { if (e > top * 0.03) last = i })
  let sum = 0, w = 0
  for (let t = 0; t < (last + 1) * 0.02; t += 0.05) { const { mag, hz } = spectrum(s, rate, t, 2048); mag.forEach((p, i) => { sum += p * i * hz; w += p }) }
  return { peak, rms: rms(s.subarray(0, (last + 1) * win)), length: (last + 1) * 0.02, centroid: sum / (w || 1) }
}
const notesAt = (s, rate, at, count = 3, size = 8192) => {
  const { mag, hz } = spectrum(s, rate, at, size)
  const peaks = []
  for (let i = 4; i < mag.length - 1; i++) if (mag[i] > mag[i - 1] && mag[i] >= mag[i + 1] && i * hz > 60) peaks.push([mag[i], i * hz])
  peaks.sort((p, q) => q[0] - p[0])
  return [...new Set(peaks.slice(0, count * 2).map(p => note(p[1])))].slice(0, count)
}

const boot = async () => {
  await emu.reset()
  await run(3000000)
}

const tests = {
  // Each effect alone, beside the app's
  async effects() {
    await boot()
    eq('the sound timer is running', (await mem(S_ON))[0], 1)
    const LIST = [['TURN', 'turn', 0.3], ['SELECT', 'select', 0.3], ['GO', 'countdownGo', 1], ['CRASH', 'crash', 1], ['WIN', 'win', 2], ['DRAW', 'draw', 1.5]]
    for (const [fx, app, secs] of LIST) {
      await request(SFX[fx])
      const cap = await capture(Math.round(secs * 60))
      await run(600000)
      const s = render(cap)
      writeWav(join(DIR, fx.toLowerCase() + '.wav'), s)
      const b = features(s, 44100)
      let line = `${fx.padEnd(6)} cart ${b.length.toFixed(2)} s, ${b.centroid.toFixed(0)} Hz, ${db(b.rms).toFixed(0)} dB, peak ${b.peak.toFixed(2)}`
      if (existsSync(join(APP, app + '.wav'))) {
        const { s: as, rate } = readWav(join(APP, app + '.wav')), a = features(as, rate)
        line += ` | app ${a.length.toFixed(2)} s, ${a.centroid.toFixed(0)} Hz, ${db(a.rms).toFixed(0)} dB`
      }
      console.log(line)
      eq(`${fx}: no tick missed`, cap.lost, 0)
    }
  },

  // The notes in the chords, where the app's have them
  async notes() {
    await boot()
    const hear = async (fx, secs) => { await request(SFX[fx]); const s = render(await capture(Math.round(secs * 60))); await run(600000); return s }
    const go = await hear('GO', 0.6)
    eq('the start: a C major chord', notesAt(go, 44100, 0.15, 4).sort(), ['C5', 'C6', 'E6', 'G6'].sort())
    const win = await hear('WIN', 1.6)
    const lead = []
    for (let t = 0; t < 0.6; t += 0.02) { const n = notesAt(win, 44100, t, 1)[0]; if (lead.at(-1) !== n) lead.push(n) }
    const start = win.findIndex(v => Math.abs(v) > 0.01) / 44100
    eq('a win rises: C5 alone first, then the strongest note goes E5, G5, C6, E6', [notesAt(win, 44100, start, 1, 2048), lead.filter(n => n !== 'C5').slice(0, 4)], [['C5'], ['E5', 'G5', 'C6', 'E6']])
    eq('and E6 rings on', notesAt(win, 44100, 0.8, 1), ['E6'])
    const draw = await hear('DRAW', 1.2)
    eq('a draw: A5, then D5 under it', [notesAt(draw, 44100, 0.05, 1), notesAt(draw, 44100, 0.4, 2).sort()], [['A5'], ['A5', 'D5']])
  },

  // What the game asks for, when
  async game() {
    await boot()
    const voices = () => mem(SF_ID, 3)
    const watch = async (cycles, ...want) => { for (let t = 0; t < cycles; t += 4000) { if ((await voices()).some(v => want.includes(v))) return true; await run(4000) } return false }
    await emu.stick(JOY.up, 'b')
    eq('moving through the menu selects', await watch(300000, SFX.SELECT), true)
    await emu.stick(0, 'b')
    await run(400000)
    await emu.stick(JOY.a, 'b')
    eq('a round starts with the chord', await watch(2000000, SFX.GO), true)
    await emu.stick(0, 'b')
    await run(1500000)
    await emu.stick(JOY.up, 'b')
    eq('a turn blips', await watch(400000, SFX.TURN), true)
    await emu.stick(0, 'b')
    eq('a crash', await watch(20000000, SFX.CRASH), true)
    eq('then the sting', await watch(4000000, SFX.WIN, SFX.DRAW), true)
    // One player riding straight on: only the CPU turns, and quietly
    await boot()
    await emu.stick(JOY.a, 'b')
    await run(200000)
    await emu.stick(0, 'b')
    await run(2500000)
    let blips = 0, turns = 0, dir = (await mem(0x47))[0]
    for (let t = 0; t < 8000000 && (await mem(0x3a))[0] === 1; t += 8000) {
      const d = (await mem(0x47))[0]
      if (d !== dir) { turns++; dir = d }
      if ((await voices())[0] === SFX.TURN) blips++
      await run(8000)
    }
    eq(`the CPU turned ${turns} times without a sound`, [turns > 0, blips], [true, 0])
  },

  // The timer keeps time through the heaviest drawing
  async steady() {
    await boot()
    const t0 = await ticks()
    await emu.stick(JOY.a, 'b')
    await run(200000)
    await emu.stick(0, 'b')
    await run(3000000)
    const n = (await ticks()) - t0, frames = Math.round(3200000 / 16683)
    eq(`${n} sound ticks in ${frames} frames, through a round starting`, Math.abs(n - frames) <= 2, true)
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
