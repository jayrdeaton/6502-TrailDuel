// One headless AC6502 emulator, driven over its debug protocol (JSON-RPC over HTTP).
//
// It needs emulator 3.0 or newer for the PICOVDP (3.6.0 is what these tests ran on).
// EMULATOR names its command line, e.g. EMULATOR=6502 or
// EMULATOR="node /path/to/6502-EMULATOR/out/cli/index.js". Without it, a checkout at
// ~/Developer/.tooling/6502-EMULATOR (built with `npm run build:cli`) is used.
import { existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs'
import { spawn } from 'node:child_process'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
export const OUT = join(here, 'out')
mkdirSync(OUT, { recursive: true })

const command = () => {
  if (process.env.EMULATOR) {
    const [cmd, ...args] = process.env.EMULATOR.split(' ')
    return [cmd, args]
  }
  const checkout = join(homedir(), 'Developer/.tooling/6502-EMULATOR/out/cli/index.js')
  if (existsSync(checkout)) return [process.execPath, [checkout]]
  return ['6502', []]
}

let nextPort = 47100 + Math.floor(Math.random() * 400)

export class Emulator {
  // Boots a machine paused, with `cart` in the slot. `save` is a file for a Flash
  // Cart's writes, or nothing to keep them only in memory (a 32 KB ROM cart has none).
  static async start({ cart, name = 'A', save, vdp = 'picovdp', extra = [] }) {
    const m = new Emulator(nextPort++, `tok${name}${process.pid}`, name)
    const [cmd, args] = command()
    m.process = spawn(cmd, [...args, 'run', '--headless', '--debug', '--pause', '--quiet', '--vdp', vdp, '--console', 'video', ...(save ? ['--cart-save', save] : statSync(cart).size > 32768 ? ['--no-cart-save'] : []), '--cart', cart, '--debug-port', String(m.port), '--debug-token', m.token, '--peer-rts', 'ignore', '--timeout', '120m', ...extra], { stdio: 'ignore' })
    for (let i = 0; i < 200; i++) {
      try {
        await m.rpc('session.info')
        return m
      } catch {
        await new Promise(r => setTimeout(r, 100))
      }
    }
    throw new Error(`emulator ${name} did not start (${cmd} ${args.join(' ')})`)
  }

  constructor(port, token, name) {
    Object.assign(this, { port, token, name, id: 0, cursor: 0 })
  }

  async rpc(method, params = {}) {
    const res = await fetch(`http://127.0.0.1:${this.port}/rpc`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${this.token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: ++this.id, method, params }) })
    const body = await res.json()
    if (body.error) throw new Error(`${this.name} ${method}: ${JSON.stringify(body.error)}`)
    return body.result
  }

  mem = async (address, length = 1) => [...Buffer.from((await this.rpc('mem.read', { address, length })).data, 'base64')]
  poke = (address, ...data) => this.rpc('mem.write', { address, data })
  run = cycles => this.rpc('exec.runCycles', { cycles })
  stick = (buttons, side = 'a') => this.rpc('input.joystick', { side, buttons })
  shot = async name => writeFileSync(join(OUT, name + '.png'), Buffer.from((await this.rpc('screen.png')).data, 'base64'))
  reset = () => this.rpc('session.reset')

  // Bytes the machine has sent out of its serial port since last asked.
  async out() {
    const r = await this.rpc('serial.read', { since: this.cursor, encoding: 'base64' })
    this.cursor = r.cursor ?? this.cursor
    return [...Buffer.from(r.data ?? '', r.encoding === 'base64' ? 'base64' : 'latin1')]
  }

  // Skip whatever has been sent so far.
  async drain() {
    this.cursor = (await this.rpc('serial.read', {})).cursor ?? 0
  }

  send = bytes => this.rpc('serial.write', { data: Buffer.from(bytes).toString('base64'), encoding: 'base64' })

  async stop() {
    await this.rpc('session.shutdown').catch(() => {})
    this.process?.kill()
  }
}

// Joystick bits, as input.joystick takes them
export const JOY = { a: 1, b: 2, up: 16, down: 32, left: 64, right: 128 }

// A tally of checks, printed as they go.
export const checks = () => {
  const t = { pass: 0, fail: 0 }
  t.eq = (name, got, want) => {
    const ok = JSON.stringify(got) === JSON.stringify(want)
    ok ? t.pass++ : t.fail++
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${JSON.stringify(got)}${ok ? '' : ' wanted ' + JSON.stringify(want)}`)
  }
  t.done = () => {
    console.log(`${t.pass} passed, ${t.fail} failed`)
    if (t.fail) process.exitCode = 1
  }
  return t
}
