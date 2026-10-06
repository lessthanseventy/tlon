// A thread read in full: the whole screen is its conversation, wrapped, scrolled from the newest
// back as far as it goes (older pages load as you reach the top), with a composer at the foot that
// grows as you write. What the reader can't do itself (send, answer, the room's verbs) it hands back.
import { ROLE } from "../kit/palette"
import type { Thread, ThreadView } from "../kit/types"
import { Editor, wrap } from "./editor"
import { ESC, line, type Seg } from "./term"

type Msg = ThreadView["messages"][number]
export type ReaderDeps = {
  /** the newest page, or the one before message `before` */
  load: (before?: number) => Promise<ThreadView | null>
  /** post as you; resolves to the status line */
  send: (body: string) => Promise<string>
  operator: string
  /** an older page arrived on its own (scrolled into): draw again */
  redraw: () => void
}

const COMPOSER_MAX = 8

export class Reader {
  private msgs: Msg[] = []
  private more = false
  private peek: string | null = null
  private loading = false
  /** rows up from the newest; 0 follows new messages as they come */
  private scroll = 0
  composer: Editor | null = null
  /** what you were writing when you stopped, back when you start again */
  private draft: Editor | null = null
  status = ""

  constructor(readonly tid: number, private readonly deps: ReaderDeps, compose = false) {
    if (compose) this.composer = new Editor()
  }

  /** take a fresh newest page, keeping the older ones already read */
  take(v: ThreadView) {
    const known = new Set(v.messages.map((m) => m.id))
    const older = this.msgs.filter((m) => !known.has(m.id) && m.id < (v.messages[0]?.id ?? Infinity))
    this.msgs = [...older, ...v.messages]
    if (!older.length) this.more = !!v.more
    this.peek = v.peek
  }
  async reload() { const v = await this.deps.load(); if (v) this.take(v) }
  private async older() {
    if (this.loading || !this.more || !this.msgs.length) return
    this.loading = true
    const v = await this.deps.load(this.msgs[0]!.id)
    this.loading = false
    if (!v) return
    this.msgs = [...v.messages, ...this.msgs]
    this.more = !!v.more
    this.deps.redraw()
  }

  /**
   * A key while reading. "leave" closes the reader, "pass" hands it to the room's own keys (the
   * thread's verbs), a promise when the key started a load or a send (redraw once it settles).
   */
  key(k: string, page: number): "leave" | "pass" | "done" | Promise<void> {
    const c = this.composer
    if (c) {
      if (k === "esc") { this.draft = c.empty ? null : c; this.composer = null; return "done" }
      if (k === "enter") {
        if (c.empty) return "done"
        const body = c.text
        this.composer = new Editor()
        this.scroll = 0
        return this.deps.send(body).then(async (s) => { this.status = s; await this.reload() })
      }
      if (k === "pgup" || k === "pgdn") return this.scrollBy(k === "pgup" ? page : -page)
      c.key(k)
      return "done"
    }
    switch (k) {
      case "esc": case "q": return "leave"
      case "r": case "i": case "enter": this.composer = this.draft ?? new Editor(); this.draft = null; return "done"
      case "j": case "down": return this.scrollBy(-1)
      case "k": case "up": return this.scrollBy(1)
      case "pgdn": case " ": return this.scrollBy(-page)
      case "pgup": case "b": return this.scrollBy(page)
      case "end": this.scroll = 0; return "done"
      case "home": this.scroll = Infinity; return this.older()
    }
    return "pass"
  }
  /** a pasted chunk goes into the composer (opening it) */
  paste(text: string) { (this.composer ??= new Editor()).insert(text) }
  private scrollBy(n: number): "done" | Promise<void> {
    this.scroll = Math.max(0, this.scroll + n)
    return "done"
  }

  /** the conversation as styled rows `width` wide, oldest first */
  private body(width: number, th: Thread | undefined): Seg[][] {
    const rows: Seg[][] = []
    if (this.more) rows.push([{ s: this.loading ? "  loading older messages…" : "  ↑ older messages — home or scroll up for them", fg: ROLE.inactive }])
    else if (this.msgs.length) rows.push([{ s: "  the start of the thread", fg: ROLE.inactive }])
    for (const m of this.msgs) {
      const you = m.author === this.deps.operator, sys = m.author === "tlon"
      rows.push([])
      rows.push([{ s: ` ${m.author}`, fg: you ? ROLE.attention : sys ? ROLE.inactive : ROLE.key, bold: true }, { s: `  ${stamp(m.at)}`, fg: ROLE.inactive }])
      for (const l of wrap(m.body, width - 3)) rows.push([{ s: `   ${l}`, fg: sys ? ROLE.inactive : ROLE.prose }])
    }
    if (!this.msgs.length && !this.peek) rows.push([{ s: "  no messages yet", fg: ROLE.inactive }])
    if (!this.msgs.length && this.peek) {
      rows.push([{ s: "  no messages yet — its terminal shows:", fg: ROLE.inactive }])
      for (const l of this.peek.split("\n").filter((x) => x.trim()).slice(-12)) rows.push([{ s: `   ${l}`, fg: ROLE.inactive }])
    }
    if (th?.prompt) {
      rows.push([])
      rows.push([{ s: " asks: ", fg: ROLE.attention, bold: true }, { s: th.prompt.summary, fg: ROLE.prose }])
      th.prompt.options?.forEach((o, i) => rows.push([{ s: `   ${i + 1} `, fg: ROLE.key }, { s: o.label, fg: ROLE.prose }]))
    } else if (th?.awaiting) rows.push([], [{ s: ` awaits ${th.awaiting}`, fg: ROLE.attention }])
    return rows
  }

  /** the whole screen; the cursor parked in the composer while you write */
  draw(cols: number, rowsN: number, th: Thread | undefined, keys: string): string {
    const c = this.composer
    const ed = c?.view(cols - 4, COMPOSER_MAX)
    const foot = c ? Math.max(1, ed!.rows.length) + 1 : 1
    const bodyH = Math.max(1, rowsN - 2 - foot)
    const all = this.body(cols, th)
    const maxScroll = Math.max(0, all.length - bodyH)
    if (this.scroll >= maxScroll && this.more) void this.older()
    this.scroll = Math.min(this.scroll, maxScroll)
    const first = Math.max(0, all.length - bodyH - this.scroll)
    // a short conversation sits on the composer, as a chat does, not at the top of an empty screen
    const pad = Math.max(0, bodyH - all.length)
    let o = `${ESC}[?2026h${ESC}[?25l${ESC}[1;1H` + line([
      { s: ` #${this.tid} `, fg: ROLE.ground, bg: ROLE.key, bold: true }, { s: ` ${th?.title ?? ""}`, fg: ROLE.body, bold: true },
      { s: `  ${th?.stage ?? "thread"}${th?.lead ? ` · ${th.lead}` : ""}${th?.live ? " · running" : ""}${this.scroll ? `  ↑${this.scroll}` : ""}`, fg: ROLE.inactive },
    ], cols)
    for (let i = 0; i < bodyH; i++) o += `${ESC}[${i + 2};1H` + line((i >= pad ? all[first + i - pad] : null) ?? [], cols)
    const top = bodyH + 2
    if (c) {
      o += `${ESC}[${top};1H` + line([{ s: " reply ", fg: ROLE.ground, bg: ROLE.attention }, { s: "  enter send · alt-enter newline · esc stop · pgup/pgdn scroll", fg: ROLE.inactive }], cols)
      ed!.rows.forEach((r, i) => { o += `${ESC}[${top + 1 + i};1H` + line([{ s: " ▌ ", fg: ROLE.attention }, { s: r, fg: ROLE.prose }], cols) })
      o += `${ESC}[${top + 1 + ed!.cursor.r};${4 + ed!.cursor.c}H${ESC}[?25h`
    } else {
      o += `${ESC}[${top};1H` + line([this.status ? { s: ` ${this.status}`, fg: ROLE.key } : { s: ` ${keys}`, fg: ROLE.inactive }], cols)
    }
    return o + `${ESC}[?2026l`
  }
}

const stamp = (at: string) => {
  const d = new Date(at)
  if (Number.isNaN(d.getTime())) return ""
  const today = new Date().toDateString() === d.toDateString()
  return today ? d.toTimeString().slice(0, 5) : `${d.toDateString().slice(4, 10)} ${d.toTimeString().slice(0, 5)}`
}
