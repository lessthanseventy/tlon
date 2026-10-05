// The terminal: raw mode on the alternate screen, SGR mouse with motion, and a tokenizer that
// turns stdin into keys, mouse events and the replies to our queries (cell size, graphics support).

export type Input =
  | { t: "key"; key: string }
  | { t: "mouse"; button: number; col: number; row: number; press: boolean; motion: boolean }
  | { t: "cell"; w: number; h: number }
  | { t: "graphics"; ok: boolean }
  | { t: "da" }

export const ESC = "\x1b"
export const out = (s: string) => process.stdout.write(s)

export function enter() {
  process.stdin.setRawMode(true)
  process.stdin.resume()
  // alt screen, hide cursor, all-motion mouse in SGR form
  out(`${ESC}[?1049h${ESC}[?25l${ESC}[?1003h${ESC}[?1006h${ESC}[2J`)
}
export function leave() {
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[?1003l${ESC}[?1006l${ESC}[?25h${ESC}[?1049l`)
  process.stdin.setRawMode(false)
}
/** ask for the cell size in pixels, and whether kitty graphics work (answered before the DA reply, or never) */
export function query() {
  out(`${ESC}[16t${ESC}_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA${ESC}\\${ESC}[c`)
}

const KEYS: Record<string, string> = {
  "[A": "up", "[B": "down", "[C": "right", "[D": "left", "[H": "home", "[F": "end", "[5~": "pgup", "[6~": "pgdn", "[Z": "backtab", "OA": "up", "OB": "down", "OC": "right", "OD": "left",
}
/** split a chunk of stdin into inputs; an unfinished escape sequence is kept for the next chunk */
export function tokenize(buf: string): { inputs: Input[]; rest: string } {
  const inputs: Input[] = []
  let i = 0
  while (i < buf.length) {
    const s = buf.slice(i)
    let m: RegExpMatchArray | null
    let len = 1
    if ((m = s.match(/^\x1b\[<(\d+);(\d+);(\d+)([Mm])/))) {
      const b = Number(m[1])
      inputs.push({ t: "mouse", button: (b & 3) | (b & 64), col: Number(m[2]), row: Number(m[3]), press: m[4] === "M", motion: (b & 32) !== 0 })
    } else if ((m = s.match(/^\x1b\[6;(\d+);(\d+)t/))) inputs.push({ t: "cell", h: Number(m[1]), w: Number(m[2]) })
    else if ((m = s.match(/^\x1b_G([^\x1b]*)\x1b\\/))) inputs.push({ t: "graphics", ok: /;OK$/.test(m[1]!) })
    else if ((m = s.match(/^\x1b\[\?[\d;]*c/))) inputs.push({ t: "da" })
    else if ((m = s.match(/^\x1b(\[[\d;]*[~A-Z]|O[A-D])/))) inputs.push({ t: "key", key: KEYS[m[1]!] ?? `esc${m[1]}` })
    // a sequence cut off at the chunk's end: wait for the rest
    else if (/^\x1b(\[[\d;<?]*|_G[^\x1b]*|_G[^\x1b]*\x1b|O)$/.test(s)) return { inputs, rest: s }
    else {
      const ch = s[0]!
      const key = ch === "\x1b" ? "esc" : ch === "\r" || ch === "\n" ? "enter" : ch === "\x7f" || ch === "\b" ? "backspace" : ch === "\t" ? "tab" : ch === "\x03" ? "ctrl-c" : ch
      inputs.push({ t: "key", key })
    }
    if (m) len = m[0]!.length
    i += len
  }
  return { inputs, rest: "" }
}

/** a run of styled text: `fg`/`bg` as #rrggbb */
export type Seg = { s: string; fg?: string; bg?: string; bold?: boolean }
const sgr = (hex: string, layer: 38 | 48) => `${ESC}[${layer};2;${parseInt(hex.slice(1, 3), 16)};${parseInt(hex.slice(3, 5), 16)};${parseInt(hex.slice(5, 7), 16)}m`
/** segments as escape-coded text, cut to `width` columns and padded to it with plain spaces */
export function line(segs: Seg[], width: number): string {
  let o = "", n = 0
  for (const g of segs) {
    if (n >= width) break
    const s = [...g.s].slice(0, width - n).join("")
    o += (g.fg ? sgr(g.fg, 38) : "") + (g.bg ? sgr(g.bg, 48) : "") + (g.bold ? `${ESC}[1m` : "") + s + `${ESC}[0m`
    n += [...s].length
  }
  return o + " ".repeat(Math.max(0, width - n))
}
