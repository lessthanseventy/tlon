// The terminal: raw mode on the alternate screen, SGR mouse with motion, and a tokenizer that
// turns stdin into keys, mouse events and the replies to our queries (cell size, graphics support).

export type Input =
  | { t: "key"; key: string }
  | { t: "paste"; text: string }
  | { t: "mouse"; button: number; col: number; row: number; press: boolean; motion: boolean }
  | { t: "cell"; w: number; h: number }
  | { t: "graphics"; ok: boolean }
  | { t: "da" }
  | { t: "focus"; on: boolean }

export const ESC = "\x1b"
let muted = false
export const out = (s: string) => { if (!muted) process.stdout.write(s) }
/** this process has handed the terminal on (a relaunch): it writes nothing more, whatever still runs */
export function mute() { muted = true }

export function enter() {
  process.stdin.setRawMode(true)
  process.stdin.resume()
  // alt screen, hide cursor, all-motion mouse in SGR form, bracketed paste (a pasted newline is
  // text, not Enter), focus reports (the margin fades only while looked at); the window titled "tlon office" (the old title saved on the terminal's
  // stack), so a window manager can match it
  out(`${ESC}[?1049h${ESC}[?25l${ESC}[?1003h${ESC}[?1006h${ESC}[?2004h${ESC}[?1004h${ESC}[2J${ESC}[22;2t${ESC}]2;tlon office${ESC}\\`)
}
export function leave() {
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[?1003l${ESC}[?1006l${ESC}[?2004l${ESC}[?1004l${ESC}[?25h${ESC}[?1049l${ESC}[23;2t`)
  process.stdin.setRawMode(false)
}
/** ask for the cell size in pixels, and whether kitty graphics work (answered before the DA reply, or never) */
export function query() {
  out(`${ESC}[16t${ESC}_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA${ESC}\\${ESC}[c`)
}

const KEYS: Record<string, string> = {
  "[A": "up", "[B": "down", "[C": "right", "[D": "left", "[H": "home", "[F": "end", "[5~": "pgup", "[6~": "pgdn", "[Z": "backtab", "OA": "up", "OB": "down", "OC": "right", "OD": "left",
  "[1~": "home", "[4~": "end", "[3~": "delete", "[13;2u": "shift-enter", "[27;2;13~": "shift-enter",
  "[1;2A": "shift-up", "[1;2B": "shift-down", "[1;2C": "shift-right", "[1;2D": "shift-left",
}
const PASTE_END = `${ESC}[201~`
/** a control character as the key it is: \r enter, \t tab, ^H/DEL backspace, the rest ctrl-<letter> */
function control(ch: string): string {
  if (ch === "\r") return "enter"
  if (ch === "\t") return "tab"
  if (ch === "\x7f" || ch === "\b") return "backspace"
  const c = ch.charCodeAt(0)
  return c < 0x20 ? `ctrl-${String.fromCharCode(c + 0x60)}` : ch
}
/** split a chunk of stdin into inputs; an unfinished escape sequence is kept for the next chunk */
export function tokenize(buf: string): { inputs: Input[]; rest: string } {
  const inputs: Input[] = []
  let i = 0
  while (i < buf.length) {
    const s = buf.slice(i)
    let m: RegExpMatchArray | null
    let len = 1
    if (s.startsWith(`${ESC}[200~`)) {
      const end = s.indexOf(PASTE_END)
      if (end < 0) return { inputs, rest: s }
      inputs.push({ t: "paste", text: s.slice(6, end) })
      i += end + PASTE_END.length
      continue
    }
    if ((m = s.match(/^\x1b\r/))) inputs.push({ t: "key", key: "alt-enter" })
    else if ((m = s.match(/^\x1b\[<(\d+);(\d+);(\d+)([Mm])/))) {
      const b = Number(m[1])
      inputs.push({ t: "mouse", button: (b & 3) | (b & 64), col: Number(m[2]), row: Number(m[3]), press: m[4] === "M", motion: (b & 32) !== 0 })
    } else if ((m = s.match(/^\x1b\[6;(\d+);(\d+)t/))) inputs.push({ t: "cell", h: Number(m[1]), w: Number(m[2]) })
    else if ((m = s.match(/^\x1b_G([^\x1b]*)\x1b\\/))) inputs.push({ t: "graphics", ok: /;OK$/.test(m[1]!) })
    else if ((m = s.match(/^\x1b\[\?[\d;]*c/))) inputs.push({ t: "da" })
    else if ((m = s.match(/^\x1b\[([IO])/))) inputs.push({ t: "focus", on: m[1] === "I" })
    else if ((m = s.match(/^\x1b(\[[\d;]*[~A-Zu]|O[A-D])/))) inputs.push({ t: "key", key: KEYS[m[1]!] ?? `esc${m[1]}` })
    // a sequence cut off at the chunk's end: wait for the rest
    else if (/^\x1b(\[[\d;<?]*|_G[^\x1b]*|_G[^\x1b]*\x1b|O)$/.test(s)) return { inputs, rest: s }
    else {
      const ch = [...s][0]!
      inputs.push({ t: "key", key: ch === "\x1b" ? "esc" : control(ch) })
      len = ch.length
    }
    if (m) len = m[0]!.length
    i += len
  }
  return { inputs, rest: "" }
}

/** a run of styled text: `fg`/`bg` as #rrggbb */
export type Seg = { s: string; fg?: string; bg?: string; bold?: boolean }
const sgr = (hex: string, layer: 38 | 48) => `${ESC}[${layer};2;${parseInt(hex.slice(1, 3), 16)};${parseInt(hex.slice(3, 5), 16)};${parseInt(hex.slice(5, 7), 16)}m`
const ZERO = /[\p{Mn}\p{Me}\p{Cf}]/u, EMOJI = /\p{Emoji_Presentation}/u
/** the columns a character takes in a terminal: none for a combining mark, two for wide (CJK, emoji) */
function charCells(ch: string): number {
  if (ZERO.test(ch)) return 0
  const c = ch.codePointAt(0)!
  if (EMOJI.test(ch)) return 2
  return (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf && c !== 0x303f) || (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) ||
    (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x20000 && c <= 0x3fffd) ? 2 : 1
}
/** the columns a string takes in a terminal */
export const cells = (s: string) => [...s].reduce((n, ch) => n + charCells(ch), 0)
/** segments as escape-coded text, cut to `width` columns and padded to it with plain spaces */
export function line(segs: Seg[], width: number): string {
  let o = "", n = 0, full = false
  for (const g of segs) {
    if (full) break
    let s = ""
    for (const ch of g.s) { const w = charCells(ch); if (n + w > width) { full = true; break } s += ch; n += w }
    o += (g.fg ? sgr(g.fg, 38) : "") + (g.bg ? sgr(g.bg, 48) : "") + (g.bold ? `${ESC}[1m` : "") + s + `${ESC}[0m`
  }
  return o + " ".repeat(Math.max(0, width - n))
}
