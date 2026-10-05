// A room's frame on a terminal. With kitty graphics the art goes up as one image, scaled by whole
// pixels so it stays crisp, its text, brackets and balloons drawn into it with a bitmap font at the
// desktop's sizes. Without, it is half blocks — two art pixels per cell — with the text as terminal
// text on the cells. Either way clicks map back to the room's logical pixels.
import type { Frame, Hit, Ink, Measure } from "../kit/canvas"
import { FONT_H, FONT_W, glyph } from "../kit/font"
import { rgb, ROLE } from "../kit/palette"
import { png } from "./png"
import { ESC, line, type Seg } from "./term"

/** where the room sits: `k` screen px per art px; cells of `cw`×`ch` px; the image's cell box */
export type Geometry = { k: number; cw: number; ch: number; col: number; row: number; cols: number; rows: number; kitty: boolean }

/** the biggest whole-pixel scale (half blocks: any fit) that leaves `below` rows for the rest */
export function geometry(W: number, H: number, termCols: number, termRows: number, below: number, cell: { w: number; h: number } | null, kitty: boolean): Geometry {
  const room = Math.max(4, termRows - below)
  if (kitty && cell) {
    // past 5× the frames get heavy to encode for no gain a sidebar can see
    const k = Math.max(1, Math.min(5, Math.floor((termCols * cell.w) / W), Math.floor((room * cell.h) / H)))
    const cols = Math.ceil((W * k) / cell.w), rows = Math.ceil((H * k) / cell.h)
    return { k, cw: cell.w, ch: cell.h, col: Math.max(0, Math.floor((termCols - cols) / 2)), row: 0, cols, rows, kitty: true }
  }
  // half blocks: a cell is one art px wide, two tall, at a scale that fits
  const k = Math.min(termCols / W, (room * 2) / H)
  const cols = Math.floor(W * k), rows = Math.floor((H * k) / 2)
  return { k, cw: 1, ch: 2, col: Math.max(0, Math.floor((termCols - cols) / 2)), row: 0, cols, rows, kitty: false }
}

/** the bitmap font's scale for a desktop text size at k×: the desktop draws `size` px at 3× */
const fontScale = (size: number, k: number) => Math.max(1, Math.floor((size * k) / 3 / FONT_H + 0.25))
/** text width in the room's logical px: the bitmap font's in kitty mode, a cell a glyph in blocks */
export const measureFor = (g: Geometry): Measure => (s, size) => (g.kitty ? s.length * FONT_W * fontScale(size, g.k) : s.length * g.cw) / g.k

/** the frame's ink, drawn into its k× art: bitmap text, corner brackets, balloons */
function inkInto(big: Uint8Array, w: number, h: number, ink: Ink[], k: number) {
  const fill = (x: number, y: number, fw: number, fh: number, c: string) => {
    const [r, g, b] = rgb(c)
    for (let j = Math.max(0, Math.round(y)); j < Math.min(h, Math.round(y + fh)); j++)
      for (let i = Math.max(0, Math.round(x)); i < Math.min(w, Math.round(x + fw)); i++) { const o = (j * w + i) * 4; big[o] = r!; big[o + 1] = g!; big[o + 2] = b!; big[o + 3] = 255 }
  }
  const write = (s: string, x: number, baseline: number, c: string, sc: number) => {
    ;[...s].forEach((ch, n) => glyph(ch).forEach((bits, row) => {
      for (let col = 0; col < FONT_W; col++) if ((bits >> (FONT_W - 1 - col)) & 1) fill(x + (n * FONT_W + col) * sc, baseline - (7 - row) * sc, sc, sc, c)
    }))
  }
  for (const i of ink) {
    if (i.t === "text") {
      const sc = fontScale(i.size, k), tw = i.s.length * FONT_W * sc
      write(i.s, i.align === "center" ? i.x * k - tw / 2 : i.x * k, i.y * k - sc, i.color, sc)
    } else if (i.t === "brackets") {
      const t = Math.max(1, Math.round(k / 2)), arm = 3 * k, x0 = i.x * k, y0 = i.y * k, x1 = (i.x + i.w) * k, y1 = (i.y + i.h) * k
      for (const [x, y, dx, dy] of [[x0, y0, 1, 1], [x1, y0, -1, 1], [x0, y1, 1, -1], [x1, y1, -1, -1]] as const) {
        fill(dx > 0 ? x : x - arm, dy > 0 ? y : y - t, arm, t, i.color)
        fill(dx > 0 ? x : x - t, dy > 0 ? y : y - arm, t, arm, i.color)
      }
    } else {
      const sc = fontScale(11, k), lh = (FONT_H + 2) * sc, pad = 3 * sc
      const bw = Math.max(...i.lines.map((l) => l.length)) * FONT_W * sc + pad * 2, bh = i.lines.length * lh + pad * 2
      const bx = Math.min(Math.max(i.cx * k - bw / 2, 2), w - bw - 2), by = Math.max(2, i.top * k - bh - 3 * k)
      fill(bx, by, bw, bh, ROLE.prose); fill(i.cx * k - k, by + bh, 2 * k, 2 * k, ROLE.prose)
      i.lines.forEach((l, n) => write(l, bx + pad, by + pad + (n + 1) * lh - 2 * sc, ROLE.fieldInk, sc))
    }
  }
}

/** the room, k× by nearest neighbour with its ink drawn in, as a kitty PNG image (id 1) at the cursor */
export function kittyImage(fr: Frame, g: Geometry): string {
  const w = fr.width * g.k, h = fr.height * g.k
  const big = new Uint8Array(w * h * 4)
  const src = new Uint32Array(fr.rgba.buffer, fr.rgba.byteOffset, fr.width * fr.height), dst = new Uint32Array(big.buffer)
  for (let y = 0; y < h; y++) {
    const sy = Math.floor(y / g.k) * fr.width, row = y * w
    for (let x = 0; x < w; x++) dst[row + x] = src[sy + Math.floor(x / g.k)]!
  }
  inkInto(big, w, h, fr.ink, g.k)
  const data = png(w, h, big).toString("base64")
  let o = `${ESC}[${g.row + 1};${g.col + 1}H`
  for (let i = 0; i < data.length; i += 4096) {
    const more = i + 4096 < data.length ? 1 : 0
    o += i === 0
      ? `${ESC}_Ga=T,f=100,i=1,p=1,q=2,C=1,z=-1,m=${more};${data.slice(i, i + 4096)}${ESC}\\`
      : `${ESC}_Gm=${more};${data.slice(i, i + 4096)}${ESC}\\`
  }
  return o
}

type Cell = { ch: string; fg?: string; bg?: string }
const hex = (r: number, g: number, b: number) => "#" + [r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")

/**
 * The room as half blocks, with the frame's ink as terminal text on the cells — where labels land on
 * the same cells, the first keeps them. One string per row, ready to write at the box's left edge.
 */
export function textLayer(fr: Frame, g: Geometry): string[] {
  const cells: (Cell & { ink?: boolean })[][] = []
  for (let r = 0; r < g.rows; r++) {
    const row: (Cell & { ink?: boolean })[] = []
    for (let c = 0; c < g.cols; c++) {
      const at = (py: number) => {
        const x = Math.min(fr.width - 1, Math.floor(c / g.k)), y = Math.min(fr.height - 1, Math.floor(py / g.k)), o = (y * fr.width + x) * 4
        return hex(fr.rgba[o]!, fr.rgba[o + 1]!, fr.rgba[o + 2]!)
      }
      row.push({ ch: "▀", fg: at(r * 2), bg: at(r * 2 + 1) })
    }
    cells.push(row)
  }
  const put = (col: number, row: number, s: string, fg: string, bg?: string) => {
    const r = cells[row]
    if (!r || [...s].some((_, i) => r[col + i]?.ink)) return
    ;[...s].forEach((ch, i) => { const c = r[col + i]; if (c) { c.ch = ch; c.fg = fg; c.bg = bg ?? c.bg; c.ink = true } })
  }
  const toCol = (x: number) => Math.floor((x * g.k) / g.cw), toRow = (y: number) => Math.floor((y * g.k - 0.01) / g.ch)
  for (const i of fr.ink) {
    if (i.t === "text") put(i.align === "center" ? toCol(i.x) - Math.floor(i.s.length / 2) : toCol(i.x), toRow(i.y), i.s, i.color)
    else if (i.t === "brackets") {
      const c0 = toCol(i.x), c1 = toCol(i.x + i.w) - 1, r0 = toRow(i.y + 0.5), r1 = toRow(i.y + i.h)
      put(c0, r0, "┌", i.color); put(c1, r0, "┐", i.color); put(c0, r1, "└", i.color); put(c1, r1, "┘", i.color)
    } else {
      const wide = Math.max(...i.lines.map((l) => l.length)) + 2
      const c0 = Math.max(0, Math.min(g.cols - wide, toCol(i.cx) - Math.floor(wide / 2))), r0 = Math.max(0, toRow(i.top) - i.lines.length - 1)
      i.lines.forEach((l, j) => put(c0, r0 + j, ` ${l.padEnd(wide - 2)} `, ROLE.fieldInk, ROLE.prose))
    }
  }
  return cells.map((r) => {
    const segs: Seg[] = []
    for (const c of r) {
      const last = segs[segs.length - 1]
      if (last && last.fg === c.fg && last.bg === c.bg) last.s += c.ch
      else segs.push({ s: c.ch, fg: c.fg, bg: c.bg })
    }
    return line(segs, g.cols)
  })
}

/** the topmost hit under a cell (1-based terminal coordinates), in the room's logical px */
export function hitAt(fr: Frame, g: Geometry, col: number, row: number): Hit | undefined {
  const c = col - 1 - g.col, r = row - 1 - g.row
  if (c < 0 || r < 0 || c >= g.cols || r >= g.rows) return undefined
  const x = ((c + 0.5) * g.cw) / g.k, y = ((r + 0.5) * g.ch) / g.k
  return fr.hits.find((h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)
}
