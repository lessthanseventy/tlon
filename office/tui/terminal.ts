// A coworker's terminal inside the office: tmux control mode on the workspace's tmux server, a
// throwaway session holding only the one window we look at (so only that window takes our size),
// its pane's output fed to a headless VT (@xterm/headless), the VT's screen drawn back as rows.
// Keys go back as raw bytes (`send-keys -H`). Nothing native: it compiles into the one binary.
import xterm from "@xterm/headless"
import type { Subprocess } from "bun"

export type Target = { socket: string; session: string; window: string }

/** tmux control mode escapes bytes under 0x20 and the backslash as \ooo; the rest is raw */
export function unescape(b: Uint8Array): Uint8Array {
  const out = new Uint8Array(b.length)
  let n = 0
  for (let i = 0; i < b.length; i++) {
    const d = (k: number) => b[i + k]! - 48
    if (b[i] === 92 && i + 3 < b.length && [1, 2, 3].every((k) => d(k) >= 0 && d(k) <= 7)) { out[n++] = d(1) * 64 + d(2) * 8 + d(3); i += 3 }
    else out[n++] = b[i]!
  }
  return out.subarray(0, n)
}

const SGR_RESET = "\x1b[0m"
type Cell = NonNullable<ReturnType<NonNullable<ReturnType<xterm.Terminal["buffer"]["active"]["getLine"]>>["getCell"]>>
function colour(c: Cell, fg: boolean): string {
  const [mode, v] = fg ? [c.getFgColorMode(), c.getFgColor()] : [c.getBgColorMode(), c.getBgColor()]
  if (fg ? c.isFgDefault() : c.isBgDefault()) return fg ? "39" : "49"
  if (fg ? c.isFgRGB() : c.isBgRGB()) return `${fg ? 38 : 48};2;${(v >> 16) & 255};${(v >> 8) & 255};${v & 255}`
  return mode !== undefined ? `${fg ? 38 : 48};5;${v}` : fg ? "39" : "49"
}
function sgr(c: Cell): string {
  const a = ["0"]
  if (c.isBold()) a.push("1")
  if (c.isDim()) a.push("2")
  if (c.isItalic()) a.push("3")
  if (c.isUnderline()) a.push("4")
  if (c.isInverse()) a.push("7")
  if (c.isStrikethrough()) a.push("9")
  a.push(colour(c, true), colour(c, false))
  return `\x1b[${a.join(";")}m`
}
/** the VT's visible screen as one SGR-coloured string per row, each exactly `cols` cells */
export function rows(t: xterm.Terminal): string[] {
  const b = t.buffer.active, out: string[] = []
  for (let y = 0; y < t.rows; y++) {
    const line = b.getLine(b.viewportY + y)
    let s = "", last = "", w = 0
    for (let x = 0; line && x < t.cols; x++) {
      const c = line.getCell(x)
      if (!c || c.getWidth() === 0) continue
      const style = sgr(c)
      if (style !== last) { s += style; last = style }
      s += c.getChars() || " "
      w += c.getWidth()
    }
    out.push(s + SGR_RESET + " ".repeat(Math.max(0, t.cols - w)))
  }
  return out
}

/**
 * One window of a coworker's tmux, live. `onChange` fires (coalesced) when the screen moved; `onExit`
 * when tmux goes away (the window closed, the server stopped).
 */
export class TerminalView {
  readonly vt: xterm.Terminal
  private readonly proc: Subprocess<"pipe", "pipe", "ignore">
  private readonly name = `tlon-office-${process.pid}-${Math.random().toString(36).slice(2, 7)}`
  private pane: string | null = null
  private pending: Uint8Array[] = []
  private replies: ((lines: string[]) => void)[] = []
  private block: string[] | null = null
  private mine = false
  private dirty = false
  closed = false

  constructor(readonly target: Target, cols: number, rowsN: number, private readonly onChange: () => void, private readonly onExit: () => void) {
    this.vt = new xterm.Terminal({ cols, rows: rowsN, allowProposedApi: true, scrollback: 0 })
    const place = "tlon-placeholder"
    this.proc = Bun.spawn(["tmux", "-L", target.socket, "-C", "new-session", "-s", this.name, "-n", place, "-x", String(cols), "-y", String(rowsN)], { stdin: "pipe", stdout: "pipe", stderr: "ignore" })
    this.read()
    void this.attach(place, cols, rowsN)
  }

  private async attach(place: string, cols: number, rowsN: number) {
    await this.cmd(`set-option -t ${this.name} destroy-unattached on`)
    await this.cmd(`link-window -s ${q(`${this.target.session}:${this.target.window}`)} -t ${this.name}:`)
    await this.cmd(`kill-window -t ${q(`=${this.name}:${place}`)}`)
    await this.cmd(`refresh-client -C ${cols}x${rowsN}`)
    const [info] = await this.cmd(`display -p -t ${this.name}: '#{pane_id} #{cursor_x} #{cursor_y} #{alternate_on}'`)
    const [pane, cx, cy] = (info ?? "").split(" ")
    if (!pane?.startsWith("%")) return this.close()
    const screen = await this.cmd(`capture-pane -p -e -t ${pane}`)
    this.vt.write(`\x1b[2J\x1b[H${screen.join("\r\n")}\x1b[${Number(cy) + 1};${Number(cx) + 1}H`)
    this.pane = pane
    for (const b of this.pending) this.vt.write(b)
    this.pending = []
    this.changed()
  }

  /** run a tmux command; its output lines (empty on %error) */
  private cmd(c: string): Promise<string[]> {
    if (this.closed) return Promise.resolve([])
    return new Promise((res) => { this.replies.push(res); this.proc.stdin.write(c + "\n"); this.proc.stdin.flush() })
  }

  private async read() {
    let buf = new Uint8Array(0)
    try {
      for await (const chunk of this.proc.stdout) {
        const joined = new Uint8Array(buf.length + chunk.length); joined.set(buf); joined.set(chunk, buf.length)
        let start = 0
        for (let i = 0; i < joined.length; i++) if (joined[i] === 10) { this.line(joined.subarray(start, i)); start = i + 1 }
        buf = joined.slice(start)
      }
    } finally { this.close() }
  }

  private line(b: Uint8Array) {
    const head = new TextDecoder().decode(b.subarray(0, Math.min(b.length, 64)))
    if (this.block) {
      if (head.startsWith("%end ") || head.startsWith("%error ")) { if (this.mine) this.replies.shift()?.(head.startsWith("%end ") ? this.block : []); this.block = null }
      else this.block.push(new TextDecoder().decode(b))
      return
    }
    // a reply block; flags 1 = one of our commands (the session's own start command answers first)
    if (head.startsWith("%begin ")) { this.block = []; this.mine = head.trim().split(" ")[3] === "1"; return }
    if (head.startsWith("%output ")) {
      const sp = head.indexOf(" ", 8), pane = head.slice(8, sp)
      if (this.pane === null) { this.pending.push(unescape(b.subarray(sp + 1))); return }
      if (pane !== this.pane) return
      this.vt.write(unescape(b.subarray(sp + 1)), () => this.changed())
      return
    }
    if (head.startsWith("%exit") || (head.startsWith("%window-close") && this.pane)) this.close()
  }

  private changed() {
    if (this.dirty) return
    this.dirty = true
    setTimeout(() => { this.dirty = false; if (!this.closed) this.onChange() }, 16)
  }

  /** what the operator typed, as the bytes the pane should get */
  send(bytes: Uint8Array) {
    if (!this.pane || !bytes.length) return
    void this.cmd(`send-keys -t ${this.pane} -H ${[...bytes].map((x) => x.toString(16).padStart(2, "0")).join(" ")}`)
  }
  resize(cols: number, rowsN: number) { this.vt.resize(cols, rowsN); void this.cmd(`refresh-client -C ${cols}x${rowsN}`) }
  close() {
    if (this.closed) return
    this.closed = true
    try { this.proc.stdin.write("detach-client\n"); this.proc.stdin.end() } catch { /* gone */ }
    setTimeout(() => this.proc.kill(), 500)
    for (const r of this.replies.splice(0)) r([])
    this.onExit()
  }
}
const q = (s: string) => `'${s.replace(/'/g, "'\\''")}'`
