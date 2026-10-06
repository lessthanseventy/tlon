// Text the TUI edits: a multi-line buffer with a cursor and the readline keys (the composer, the
// one-line prompts), and word wrap for anything shown in a fixed width.

/** a line of text cut at word boundaries into rows at most `width` wide; a word longer than a row is split */
export function wrap(text: string, width: number): string[] {
  const w = Math.max(1, width), out: string[] = []
  for (const para of text.split("\n")) {
    let row = ""
    for (const word of para.split(/(\s+)/)) {
      if (!word) continue
      if ([...row].length + [...word].length <= w) { row += word; continue }
      if (row.trim()) out.push(row.trimEnd())
      row = /^\s+$/.test(word) ? "" : word
      while ([...row].length > w) { out.push([...row].slice(0, w).join("")); row = [...row].slice(w).join("") }
    }
    out.push(row.trimEnd())
  }
  return out
}

const isWord = (c: string | undefined) => !!c && /[\p{L}\p{N}_]/u.test(c)

export class Editor {
  lines: string[][]
  row = 0
  col = 0
  constructor(text = "", readonly multiline = true) {
    this.lines = text.split("\n").map((l) => [...l])
    this.row = this.lines.length - 1
    this.col = this.lines[this.row]!.length
  }
  get text() { return this.lines.map((l) => l.join("")).join("\n") }
  get empty() { return !this.text.trim() }
  private get line() { return this.lines[this.row]! }

  insert(s: string) {
    const parts = (this.multiline ? s : s.replace(/\r?\n/g, " ")).replace(/\r\n?/g, "\n").split("\n")
    parts.forEach((p, i) => {
      if (i) this.newline()
      const chars = [...p].filter((c) => c >= " " || c === "\t")
      this.line.splice(this.col, 0, ...chars)
      this.col += chars.length
    })
  }
  newline() {
    if (!this.multiline) return
    const rest = this.line.splice(this.col)
    this.lines.splice(++this.row, 0, rest)
    this.col = 0
  }
  /**
   * A key the editor understands, applied; false for one it leaves to its owner (enter, esc, tab,
   * the scroll keys). Newline is alt-enter, shift-enter or ctrl-j: a plain enter is the owner's.
   */
  key(k: string): boolean {
    const l = this.line
    switch (k) {
      case "alt-enter": case "shift-enter": case "ctrl-j": if (!this.multiline) return false; this.newline(); return true
      case "backspace":
        if (this.col > 0) l.splice(--this.col, 1)
        else if (this.row > 0) { const prev = this.lines[this.row - 1]!; this.col = prev.length; prev.push(...l); this.lines.splice(this.row--, 1) }
        return true
      case "delete": case "ctrl-d":
        if (this.col < l.length) l.splice(this.col, 1)
        else if (this.row < this.lines.length - 1) l.push(...this.lines.splice(this.row + 1, 1)[0]!)
        return true
      case "left": case "ctrl-b":
        if (this.col > 0) this.col--
        else if (this.row > 0) this.col = this.lines[--this.row]!.length
        return true
      case "right": case "ctrl-f":
        if (this.col < l.length) this.col++
        else if (this.row < this.lines.length - 1) { this.row++; this.col = 0 }
        return true
      case "up": case "ctrl-p":
        if (!this.multiline || this.row === 0) return false
        this.col = Math.min(this.col, this.lines[--this.row]!.length); return true
      case "down": case "ctrl-n":
        if (!this.multiline || this.row === this.lines.length - 1) return false
        this.col = Math.min(this.col, this.lines[++this.row]!.length); return true
      case "home": case "ctrl-a": this.col = 0; return true
      case "end": case "ctrl-e": this.col = l.length; return true
      case "ctrl-u": l.splice(0, this.col); this.col = 0; return true
      case "ctrl-k": l.splice(this.col); return true
      case "ctrl-w": {
        let i = this.col
        while (i > 0 && !isWord(l[i - 1])) i--
        while (i > 0 && isWord(l[i - 1])) i--
        l.splice(i, this.col - i); this.col = i
        return true
      }
    }
    if ([...k].length === 1 && k >= " ") { this.insert(k); return true }
    return false
  }

  /**
   * The buffer soft-wrapped to `width`, the last `height` rows that keep the cursor in view, and
   * where the cursor lands among them.
   */
  view(width: number, height: number): { rows: string[]; cursor: { r: number; c: number } } {
    const w = Math.max(1, width), rows: string[] = []
    let cursor = { r: 0, c: 0 }
    this.lines.forEach((l, i) => {
      const chunks = l.length ? Array.from({ length: Math.ceil(l.length / w) }, (_, j) => l.slice(j * w, (j + 1) * w).join("")) : [""]
      if (i === this.row) {
        const j = Math.min(Math.floor(this.col / w), chunks.length)
        if (j === chunks.length) chunks.push("")
        cursor = { r: rows.length + j, c: this.col - j * w }
      }
      rows.push(...chunks)
    })
    const first = Math.max(0, Math.min(rows.length - height, cursor.r - height + 1))
    return { rows: rows.slice(first, first + height), cursor: { r: cursor.r - first, c: cursor.c } }
  }
}
