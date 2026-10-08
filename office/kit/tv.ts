// The TV's channels: the desktop backdrop's ambient shows (ficciones' shell/lib/ambient.ts), retuned
// for a screen a few dozen pixels wide, and an aquarium of the office's own. Each is a pure `step` over a dot screen, one art pixel a
// dot, in five hues that are roles, so a theme switch recolours them.
import { SMALL } from "./font"
import { ROLE, type Role } from "./palette"

const HUES: Role[] = ["body", "live", "attention", "key", "meta"]
export const hueRole = (h: number) => ROLE[HUES[h % HUES.length]!]

/** a w×h dot screen: 0 dark, else the dot's hue + 1 */
export class Screen {
  readonly dots: Uint8Array
  constructor(readonly w: number, readonly h: number) { this.dots = new Uint8Array(w * h) }
  clear() { this.dots.fill(0) }
  /** fade lit dots out at random — the phosphor */
  decay(p: number) { for (let i = 0; i < this.dots.length; i++) if (this.dots[i] && Math.random() < p) this.dots[i] = 0 }
  plot(x: number, y: number, hue = 0) {
    const cx = Math.floor(x), cy = Math.floor(y)
    if (cx >= 0 && cy >= 0 && cx < this.w && cy < this.h) this.dots[cy * this.w + cx] = hue + 1
  }
}

type Show = { name: string; init(s: Screen): void; step(s: Screen): void }

const lorenz = (): Show => {
  let t: { x: number; y: number; z: number }[] = []
  return {
    name: "lorenz",
    init(s) { s.clear(); t = [{ x: 0.1, y: 0, z: 0 }, { x: -0.2, y: 0.1, z: 20 }, { x: 8, y: 8, z: 27 }] },
    step(s) {
      s.decay(0.05)
      t.forEach((p, k) => {
        for (let i = 0; i < 12; i++) {
          const dt = 0.004, dx = 10 * (p.y - p.x), dy = p.x * (28 - p.z) - p.y, dz = p.x * p.y - (8 / 3) * p.z
          p.x += dx * dt; p.y += dy * dt; p.z += dz * dt
          s.plot(((p.x + 24) / 48) * s.w, (1 - (p.z - 2) / 50) * s.h, k)
        }
      })
    },
  }
}

const life = (): Show => {
  let a = new Uint8Array(0), b = new Uint8Array(0), age = new Uint8Array(0), still = 0, last = -1
  const seed = (s: Screen) => { a = Uint8Array.from({ length: s.w * s.h }, () => (Math.random() < 0.3 ? 1 : 0)); b = new Uint8Array(a.length); age = new Uint8Array(a.length); still = 0 }
  return {
    name: "life",
    init: seed,
    step(s) {
      const { w, h } = s
      let pop = 0
      for (let y = 0; y < h; y++) {
        const up = ((y - 1 + h) % h) * w, mid = y * w, dn = ((y + 1) % h) * w
        for (let x = 0; x < w; x++) {
          const l = x === 0 ? w - 1 : x - 1, r = x === w - 1 ? 0 : x + 1
          const n = a[up + l]! + a[up + x]! + a[up + r]! + a[mid + l]! + a[mid + r]! + a[dn + l]! + a[dn + x]! + a[dn + r]!
          pop += b[mid + x] = n === 3 || (n === 2 && a[mid + x]) ? 1 : 0
        }
      }
      ;[a, b] = [b, a]
      // a screen this small settles fast: a fresh soup once it has gone still
      still = pop === last ? still + 1 : 0; last = pop
      if (still > 30 || pop < 8) seed(s)
      s.clear()
      for (let i = 0; i < a.length; i++) {
        if (!a[i]) { age[i] = 0; continue }
        const t = (age[i] = Math.min(255, age[i]! + 1))
        s.plot(i % w, (i / w) | 0, t < 3 ? 1 : t < 12 ? 0 : t < 40 ? 3 : 4)
      }
    },
  }
}

const boids = (): Show => {
  let flock: { x: number; y: number; vx: number; vy: number; hue: number }[] = []
  return {
    name: "boids",
    init(s) { s.clear(); flock = Array.from({ length: 16 }, (_, i) => ({ x: Math.random() * s.w, y: Math.random() * s.h, vx: Math.random() - 0.5, vy: Math.random() - 0.5, hue: i % 5 })) },
    step(s) {
      s.decay(0.3)
      for (const b of flock) {
        let cx = 0, cy = 0, ax = 0, ay = 0, sx = 0, sy = 0, n = 0
        for (const o of flock) {
          if (o === b) continue
          const dx = o.x - b.x, dy = o.y - b.y, d2 = dx * dx + dy * dy
          if (d2 < 100) { cx += o.x; cy += o.y; ax += o.vx; ay += o.vy; n++; if (d2 < 6) { sx -= dx; sy -= dy } }
        }
        if (n) {
          b.vx += (cx / n - b.x) * 0.006 + (ax / n - b.vx) * 0.05 + sx * 0.05
          b.vy += (cy / n - b.y) * 0.006 + (ay / n - b.vy) * 0.05 + sy * 0.05
        }
        const sp = Math.hypot(b.vx, b.vy) || 1
        if (sp > 0.7) { b.vx = (b.vx / sp) * 0.7; b.vy = (b.vy / sp) * 0.7 }
        b.x = (b.x + b.vx + s.w) % s.w; b.y = (b.y + b.vy + s.h) % s.h
        s.plot(b.x, b.y, b.hue)
      }
    },
  }
}

const rule30 = (): Show => {
  let row = new Uint8Array(0), rows: Uint8Array[] = []
  return {
    name: "rule 30",
    init(s) { s.clear(); row = new Uint8Array(s.w); row[s.w >> 1] = 1; rows = [] },
    step(s) {
      const w = row.length, next = new Uint8Array(w)
      for (let x = 0; x < w; x++) next[x] = (row[(x - 1 + w) % w]! ^ (row[x]! | row[(x + 1) % w]!)) & 1
      row = next; rows.push(row)
      if (rows.length > s.h) rows.shift()
      s.clear()
      rows.forEach((r, y) => { for (let x = 0; x < w; x++) if (r[x]) s.plot(x, y, rows.length - 1 - y < s.h / 3 ? 3 : 4) })
    },
  }
}

const pipes = (): Show => {
  type P = { x: number; y: number; dx: number; dy: number; hue: number }
  let ps: P[] = [], laid = 0, fading = 0
  const edge = (s: Screen, hue: number): P => {
    const d = Math.random() < 0.5 ? 1 : -1
    return Math.random() < 0.5
      ? { x: d > 0 ? 0 : s.w - 1, y: Math.floor((Math.random() * s.h) / 4) * 4, dx: d, dy: 0, hue }
      : { x: Math.floor((Math.random() * s.w) / 4) * 4, y: d > 0 ? 0 : s.h - 1, dx: 0, dy: d, hue }
  }
  const start = (s: Screen) => { s.clear(); laid = 0; fading = 0; ps = [0, 1, 3].map((h) => edge(s, h)) }
  return {
    name: "pipes",
    init: start,
    step(s) {
      if (fading) { s.decay(0.1); if (++fading > 25) start(s); return }
      for (const p of ps) {
        // turns only on the lattice, so runs lie parallel like the terminal's
        if (p.x % 4 === 0 && p.y % 4 === 0 && Math.random() < 0.25) { const [dx, dy] = Math.random() < 0.5 ? [-p.dy, p.dx] : [p.dy, -p.dx]; p.dx = dx; p.dy = dy }
        p.x += p.dx; p.y += p.dy
        if (p.x < 0 || p.y < 0 || p.x >= s.w || p.y >= s.h) Object.assign(p, edge(s, p.hue))
        s.plot(p.x, p.y, p.hue)
      }
      if ((laid += ps.length) > s.w * s.h * 0.5) fading = 1
    },
  }
}

const bonsai = (): Show => {
  type B = { x: number; y: number; a: number; life: number; depth: number }
  const UP = -Math.PI / 2
  let br: B[] = [], hold = 0, fading = 0, trunk = 0
  const start = (s: Screen) => {
    s.clear(); hold = 0; fading = 0
    const x0 = Math.round(s.w * (0.35 + Math.random() * 0.3)), top = s.h - 4, hw = 6
    for (let x = -hw; x <= hw; x++) s.plot(x0 + x, top, 4)
    for (let r = 1; r <= 3; r++) { s.plot(x0 - hw + r, top + r, 4); s.plot(x0 + hw - r, top + r, 4) }
    for (let x = -hw + 3; x <= hw - 3; x++) s.plot(x0 + x, top + 3, 4)
    trunk = s.h * (0.3 + Math.random() * 0.1)
    br = [{ x: x0, y: top, a: UP, life: trunk, depth: 0 }]
  }
  return {
    name: "bonsai",
    init: start,
    step(s) {
      if (fading) { s.decay(0.08); if (++fading > 30) start(s); return }
      if (!br.length) { if (++hold > 60) fading = 1; return }
      const next: B[] = []
      for (const b of br) {
        b.a += (Math.random() - 0.5) * 0.3 + (UP - b.a) * (b.depth ? 0.02 : 0.08)
        b.x += Math.cos(b.a) * 0.7; b.y += Math.sin(b.a) * 0.7
        s.plot(b.x, b.y, 0); if (!b.depth) s.plot(b.x + 1, b.y, 0)
        if (b.x < 0 || b.x >= s.w || b.y < 0) continue
        if (--b.life > 0) { next.push(b); continue }
        if (b.depth >= 2) for (let i = 0; i < (b.depth >= 3 ? 7 : 3); i++) { const r = Math.random() * 2.5, t = Math.random() * Math.PI * 2; s.plot(b.x + Math.cos(t) * r * 1.3, b.y + Math.sin(t) * r, Math.random() < 0.15 ? 2 : 1) }
        if (b.depth >= 4) continue
        for (const side of b.depth === 0 ? [-1, 0, 1] : [-1, 1]) next.push({ x: b.x, y: b.y, a: b.a + side * (0.4 + Math.random() * 0.5), life: trunk * 0.55 * 0.72 ** b.depth * (0.7 + Math.random() * 0.6), depth: b.depth + 1 })
      }
      br = next
    },
  }
}

const maze = (): Show => {
  const C = 4
  let cw = 0, ch = 0, seen = new Uint8Array(0), par = new Int32Array(0), stack: number[] = [], path: number[] = [], k = 0, hold = 0, fading = 0
  const seg = (s: Screen, a: number, b: number, hue: number) => {
    const ax = (a % cw) * C + C / 2, ay = Math.floor(a / cw) * C + C / 2, bx = (b % cw) * C + C / 2, by = Math.floor(b / cw) * C + C / 2
    for (let i = 0; i <= C; i++) s.plot(ax + ((bx - ax) * i) / C, ay + ((by - ay) * i) / C, hue)
  }
  const start = (s: Screen) => {
    s.clear(); cw = Math.floor(s.w / C); ch = Math.floor(s.h / C)
    seen = new Uint8Array(cw * ch); par = new Int32Array(cw * ch).fill(-1); stack = [0]; seen[0] = 1; path = []; k = 0; hold = 0; fading = 0
  }
  return {
    name: "maze",
    init: start,
    step(s) {
      if (fading) { s.decay(0.1); if (++fading > 25) start(s); return }
      if (stack.length) {
        for (let n = 0; n < 2 && stack.length; n++) {
          const c = stack[stack.length - 1]!, x = c % cw, y = Math.floor(c / cw), nb: number[] = []
          if (x > 0 && !seen[c - 1]) nb.push(c - 1)
          if (x < cw - 1 && !seen[c + 1]) nb.push(c + 1)
          if (y > 0 && !seen[c - cw]) nb.push(c - cw)
          if (y < ch - 1 && !seen[c + cw]) nb.push(c + cw)
          if (!nb.length) { stack.pop(); continue }
          const d = nb[Math.floor(Math.random() * nb.length)]!
          seen[d] = 1; par[d] = c; stack.push(d); seg(s, c, d, 4)
        }
        // carved: the carving is a tree from the first cell, so the way to the last is its parents
        if (!stack.length) for (let c = cw * ch - 1; c > 0; c = par[c]!) path.unshift(c)
        return
      }
      if (k < path.length) { seg(s, k ? path[k - 1]! : 0, path[k]!, 2); k++; return }
      if (++hold > 50) fading = 1
    },
  }
}

const stars = (): Show => {
  type S = { x: number; y: number; z: number }
  let st: S[] = []
  const born = (z: number): S => ({ x: Math.random() * 2 - 1, y: Math.random() * 2 - 1, z })
  return {
    name: "stars",
    init(s) { s.clear(); st = Array.from({ length: 36 }, () => born(0.1 + Math.random() * 0.9)) },
    step(s) {
      s.decay(0.5)
      for (const p of st) {
        p.z -= 0.012
        const x = s.w / 2 + (p.x / p.z) * s.h * 0.5, y = s.h / 2 + (p.y / p.z) * s.h * 0.5
        if (p.z <= 0.03 || x < 0 || x >= s.w || y < 0 || y >= s.h) { Object.assign(p, born(1)); continue }
        s.plot(x, y, p.z < 0.25 ? 0 : p.z < 0.55 ? 3 : 4)
      }
    },
  }
}

const flow = (): Show => {
  type F = { x: number; y: number; life: number; hue: number }
  let ps: F[] = [], t = 0
  const spawn = (s: Screen, p: F) => Object.assign(p, { x: Math.random() * s.w, y: Math.random() * s.h, life: 20 + Math.random() * 50, hue: Math.random() < 0.7 ? 3 : Math.random() < 0.6 ? 1 : 4 })
  const angle = (x: number, y: number) => Math.sin(x * 0.13 + t) * 1.6 + Math.cos(y * 0.18 - t * 0.7) * 1.4 + Math.sin((x + y) * 0.06 + t * 0.4)
  return {
    name: "flow",
    init(s) { s.clear(); t = Math.random() * 100; ps = Array.from({ length: 40 }, () => spawn(s, { x: 0, y: 0, life: 0, hue: 3 })) },
    step(s) {
      s.decay(0.12); t += 0.01
      for (const p of ps) {
        const a = angle(p.x, p.y); p.x += Math.cos(a) * 0.5; p.y += Math.sin(a) * 0.5; s.plot(p.x, p.y, p.hue)
        if (--p.life < 0 || p.x < 0 || p.x >= s.w || p.y < 0 || p.y >= s.h) spawn(s, p)
      }
    },
  }
}

const ant = (): Show => {
  const DX = [0, 1, 0, -1], DY = [-1, 0, 1, 0]
  let cells = new Uint8Array(0), ants: { x: number; y: number; d: number; hue: number }[] = [], on = 0
  const start = (s: Screen) => {
    s.clear(); cells = new Uint8Array(s.w * s.h); on = 0
    ants = [0, 1, 3].map((hue) => ({ x: Math.floor(s.w * (0.3 + Math.random() * 0.4)), y: Math.floor(s.h * (0.3 + Math.random() * 0.4)), d: Math.floor(Math.random() * 4), hue }))
  }
  return {
    name: "ant",
    init: start,
    step(s) {
      for (const a of ants) for (let i = 0; i < 12; i++) {
        const k = a.y * s.w + a.x
        if (cells[k]) { a.d = (a.d + 3) & 3; cells[k] = 0; on-- } else { a.d = (a.d + 1) & 3; cells[k] = a.hue + 1; on++ }
        a.x = (a.x + DX[a.d]! + s.w) % s.w; a.y = (a.y + DY[a.d]! + s.h) % s.h
      }
      if (on > (s.w * s.h) / 4) return start(s)
      s.dots.set(cells)
    },
  }
}

const rain = (): Show => {
  let rings: { x: number; y: number; r: number; max: number }[] = []
  return {
    name: "rain",
    init(s) { s.clear(); rings = [] },
    step(s) {
      if (rings.length < (s.w * s.h) / 250 && Math.random() < 0.3) rings.push({ x: Math.random() * s.w, y: s.h * 0.1 + Math.random() * s.h * 0.85, r: 0, max: 4 + Math.random() * 8 })
      s.clear()
      rings = rings.filter((q) => (q.r += 0.35) < q.max)
      for (const q of rings) {
        const life = 1 - q.r / q.max, n = Math.ceil(q.r * 5)
        for (let j = 0; j < n; j++) if (Math.random() < life + 0.2) { const a = (j / n) * Math.PI * 2; s.plot(q.x + Math.cos(a) * q.r, q.y + Math.sin(a) * q.r * 0.5, life > 0.5 ? 3 : 4) }
      }
    },
  }
}

// fish facing right (mirrored to swim left): "x" the body in its hue, "e" its eye
const FISH = [["xx.", "xxe", "xx."], [".xxx.", "xxxxe", ".xxx."], ["x..xxx..", "xxxxxxxe", "x..xxx.."]]
const WHALE = ["....xxxxxx....", "x.xxxxxxxxxx..", "xxxxxxxxxxxexx", "x.xxxxxxxxxxxx", "....xxxxxxxx.."]

const aquarium = (): Show => {
  type Fish = { x: number; y: number; v: number; hue: number; rows: string[] }
  let fish: Fish[] = [], bubbles: { x: number; y: number }[] = [], t = 0
  const spawn = (s: Screen, anywhere: boolean): Fish => {
    const rows = FISH[Math.floor(Math.random() * FISH.length)]!, v = (0.15 + Math.random() * 0.35) * (Math.random() < 0.5 ? 1 : -1), w = rows[0]!.length
    return { x: anywhere ? Math.random() * s.w : v > 0 ? -w : s.w, y: 1 + Math.floor(Math.random() * (s.h - 7)), v, hue: [0, 2, 3, 4][Math.floor(Math.random() * 4)]!, rows }
  }
  const draw = (s: Screen, f: Fish) => f.rows.forEach((r, j) => [...r].forEach((ch, i) => {
    if (ch === ".") return
    s.plot(f.v > 0 ? f.x + i : f.x + r.length - 1 - i, f.y + j, ch === "e" ? 1 : f.hue)
  }))
  return {
    name: "aquarium",
    init(s) { s.clear(); t = 0; bubbles = []; fish = Array.from({ length: Math.max(3, Math.floor((s.w * s.h) / 200)) }, () => spawn(s, true)) },
    step(s) {
      s.clear(); t++
      // the sand, the weed swaying in it, the bubbles going up
      for (let x = 0; x < s.w; x++) if ((x * 7 + 3) % 5) s.plot(x, s.h - 1, 0)
      for (const wx of [3, Math.floor(s.w / 3), Math.floor((s.w * 2) / 3) + 2, s.w - 4]) for (let j = 1; j < 6 + (wx % 4); j++) s.plot(wx + Math.round(Math.sin(t / 8 + j / 2) * (j / 4)), s.h - 1 - j, 1)
      if (Math.random() < 0.15) bubbles.push({ x: 2 + Math.random() * (s.w - 4), y: s.h - 2 })
      bubbles = bubbles.filter((b) => (b.y -= 0.4) > 0)
      for (const b of bubbles) s.plot(b.x + Math.sin(b.y), b.y, 3)
      for (const f of fish) { f.x += f.v; draw(s, f) }
      fish = fish.map((f) => (f.x < -f.rows[0]!.length - 1 || f.x > s.w + 1 ? spawn(s, false) : f))
      // now and then something big goes by, slowly
      if (!fish.some((f) => f.rows === WHALE) && Math.random() < 0.004) fish.push({ x: -WHALE[0]!.length, y: 4, v: 0.12, hue: 4, rows: WHALE })
    },
  }
}

/** the TV: a screen, its channels in turn (a minute each), and the remote */
export class Tv {
  readonly screen: Screen
  private readonly shows = [lorenz(), life(), boids(), rule30(), pipes(), bonsai(), maze(), stars(), flow(), ant(), rain(), aquarium()]
  private idx = Math.floor(Math.random() * this.shows.length)
  private ticks = 0
  constructor(w: number, h: number) { this.screen = new Screen(w, h); this.shows[this.idx]!.init(this.screen) }
  get channel() { return this.levelLeft > 0 ? "level" : this.shows[this.idx]!.name }
  /** the level channel: "LEVEL" and the number, for `frames`, then the interrupted show again */
  showLevel(n: number, frames = 150) { this.level = n; this.levelLeft = frames }
  private level = 0
  private levelLeft = 0
  private drawText(text: string, y: number, scale: number, hue: number) {
    const s = this.screen, x0 = Math.floor((s.w - text.length * SMALL.w * scale) / 2)
    ;[...text].forEach((ch, i) => SMALL.glyph(ch).forEach((bits, r) => {
      for (let c = 0; c < SMALL.w; c++) if (bits & (1 << (SMALL.w - 1 - c))) for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) s.plot(x0 + (i * SMALL.w + c) * scale + dx, y + r * scale + dy, hue)
    }))
  }
  /** one frame of the show; changes channel every 300 frames */
  step() {
    if (this.levelLeft > 0) {
      this.screen.clear()
      this.drawText("LEVEL", 2, 1, 3)
      this.drawText(String(this.level), 13, 2, this.levelLeft % 8 < 4 ? 1 : 2)
      if (--this.levelLeft === 0) { this.screen.clear(); this.shows[this.idx]!.init(this.screen) }
      return
    }
    if (++this.ticks % 300 === 0) return this.next()
    this.shows[this.idx]!.step(this.screen)
  }
  next() { this.idx = (this.idx + 1) % this.shows.length; this.ticks = 0; this.shows[this.idx]!.init(this.screen) }
}
