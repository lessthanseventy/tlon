// A room's frame on a terminal. With kitty graphics the art goes up as one image, scaled by whole
// pixels so it stays crisp, its text, brackets and balloons drawn into it with a bitmap font at the
// desktop's sizes. Without, it is half blocks — two art pixels per cell — with the text as terminal
// text on the cells. Either way clicks map back to the room's logical pixels.
import { balloonLines, type Frame, type Hit, type Ink, type Measure } from "../kit/canvas"
import { placeBox, type Box } from "../kit/balloon"
import { BODY, SMALL, type Cut } from "../kit/font"
import { contrast, rgb, ROLE } from "../kit/palette"
import { png } from "./png"
import { ESC, line, type Seg } from "./term"
import type { Viewport } from "./viewport"

/** where the room sits: `k` screen px per art px; cells of `cw`×`ch` px; the image's cell box; the floor's own size */
export type Geometry = { k: number; cw: number; ch: number; col: number; row: number; cols: number; rows: number; kitty: boolean; floorW: number; floorH: number }

/** the biggest whole-pixel scale that fits `fitH` (default the floor's height), or a flat legible 2× once that no longer fits at all;
 *  a floor taller than `fitH` (the wide room's home annex) keeps that scale and pans in the viewport rather than shrinking the room */
export function geometry(W: number, H: number, termCols: number, termRows: number, below: number, cell: { w: number; h: number } | null, kitty: boolean, fitH = H): Geometry {
  const room = Math.max(4, termRows - below)
  if (kitty && cell) {
    // past 5× the frames get heavy to encode for no gain a sidebar can see
    const naturalK = Math.min(Math.floor((termCols * cell.w) / W), Math.floor((room * cell.h) / fitH))
    const k = naturalK >= 1 ? Math.max(1, Math.min(5, naturalK)) : 2
    const cols = Math.min(termCols, Math.ceil((W * k) / cell.w)), rows = Math.min(room, Math.ceil((H * k) / cell.h))
    return { k, cw: cell.w, ch: cell.h, col: Math.max(0, Math.floor((termCols - cols) / 2)), row: 0, cols, rows, kitty: true, floorW: W, floorH: H }
  }
  // half blocks: a cell is one art px wide, two tall, at a scale that fits
  const k = Math.min(termCols / W, (room * 2) / fitH)
  const cols = Math.floor(W * k), rows = Math.floor((H * k) / 2)
  return { k, cw: 1, ch: 2, col: Math.max(0, Math.floor((termCols - cols) / 2)), row: 0, cols, rows, kitty: false, floorW: W, floorH: H }
}

/**
 * The room's text grows with the terminal's: 1× in an 18 px cell, 2× at double the zoom (WCAG
 * 1.4.4), every step together — but never past half the room's own scale, the ratio its labels are
 * laid out for: a zoomed terminal too narrow to scale the room up keeps the text where it fits.
 */
export const textScale = (g: Geometry) => Math.max(1, Math.min(Math.round(g.ch / 18), Math.floor(g.k / 2)))
/**
 * The type scale, from a text's size hint: under 10 the small cut (asides: whiteboard items, the
 * clock), 10..12 the body cut (names, headers, balloons), 13 and up the small cut doubled (call-outs).
 */
export function typeFor(size: number, zoom: number): { font: Cut; sc: number } {
  return size < 10 ? { font: SMALL, sc: zoom } : size < 13 ? { font: BODY, sc: zoom } : { font: SMALL, sc: 2 * zoom }
}
/** text width (and line height) in the room's logical px: the bitmap font's in kitty mode, a cell a glyph in blocks */
export function measureFor(g: Geometry): Measure {
  const zoom = textScale(g)
  const m: Measure = (s, size) => { const { font, sc } = typeFor(size, zoom); return (g.kitty ? s.length * font.w * sc : s.length * g.cw) / g.k }
  m.lineHeight = (size) => { const { font, sc } = typeFor(size, zoom); return (g.kitty ? font.h * sc + 2 : g.ch) / g.k }
  return m
}

/** WCAG AA for text */
export const MIN_CONTRAST = 4.5
/** a solid backing for text that would not read against its art: the dark or the light role, whichever contrasts more */
export function backingFor(text: string) { return contrast(text, ROLE.ground) >= contrast(text, ROLE.prose) ? ROLE.ground : ROLE.prose }

/**
 * The frame's ink, drawn into its k× art: bitmap text at the terminal's size, corner brackets,
 * balloons. Text whose colour falls under 4.5:1 against the art behind it gets a solid backing
 * (WCAG 1.4.3); `backed` collects each label's colour and the colour actually behind it.
 */
export function inkInto(big: Uint8Array, w: number, h: number, ink: Ink[], k: number, zoom: number, backed?: { text: string; behind: string }[], view: Box = { x: 0, y: 0, w, h }) {
  const taken: Box[] = []
  const fill = (x: number, y: number, fw: number, fh: number, c: string) => {
    const [r, g, b] = rgb(c)
    for (let j = Math.max(0, Math.round(y)); j < Math.min(h, Math.round(y + fh)); j++)
      for (let i = Math.max(0, Math.round(x)); i < Math.min(w, Math.round(x + fw)); i++) { const o = (j * w + i) * 4; big[o] = r!; big[o + 1] = g!; big[o + 2] = b!; big[o + 3] = 255 }
  }
  const write = (s: string, x: number, baseline: number, c: string, font: Cut, sc: number) => {
    ;[...s].forEach((ch, n) => font.glyph(ch).forEach((bits, row) => {
      for (let col = 0; col < font.w; col++) if ((bits >> (font.w - 1 - col)) & 1) fill(x + (n * font.w + col) * sc, baseline - (font.ascent - row) * sc, sc, sc, c)
    }))
  }
  // the art's average colour under a box, as #rrggbb
  const behind = (x: number, y: number, bw: number, bh: number) => {
    let r = 0, g = 0, b = 0, n = 0
    for (let j = Math.max(0, Math.round(y)); j < Math.min(h, Math.round(y + bh)); j++)
      for (let i = Math.max(0, Math.round(x)); i < Math.min(w, Math.round(x + bw)); i++) { const o = (j * w + i) * 4; r += big[o]!; g += big[o + 1]!; b += big[o + 2]!; n++ }
    return n ? "#" + [r, g, b].map((v) => Math.round(v / n).toString(16).padStart(2, "0")).join("") : ROLE.ground
  }
  for (const i of ink) {
    if (i.t === "text") {
      const { font, sc } = typeFor(i.size, zoom), tw = i.s.length * font.w * sc, th = font.h * sc
      const x = Math.round(i.align === "center" ? i.x * k - tw / 2 : i.x * k), base = Math.round(i.y * k - sc)
      let bg = behind(x, base - font.ascent * sc, tw, th)
      if (contrast(i.color, bg) < MIN_CONTRAST) { bg = backingFor(i.color); fill(x - sc, base - font.ascent * sc - sc, tw + 2 * sc, th + 2 * sc, bg) }
      backed?.push({ text: i.color, behind: bg })
      write(i.s, x, base, i.color, font, sc)
    } else if (i.t === "brackets") {
      const t = Math.max(1, Math.round(k / 2)), arm = 3 * k, x0 = i.x * k, y0 = i.y * k, x1 = (i.x + i.w) * k, y1 = (i.y + i.h) * k
      for (const [x, y, dx, dy] of [[x0, y0, 1, 1], [x1, y0, -1, 1], [x0, y1, 1, -1], [x1, y1, -1, -1]] as const) {
        fill(dx > 0 ? x : x - arm, dy > 0 ? y : y - t, arm, t, i.color)
        fill(dx > 0 ? x : x - t, dy > 0 ? y : y - arm, t, arm, i.color)
      }
    } else {
      const font = BODY, sc = zoom, lh = (font.h + 1) * sc, pad = 4 * sc
      const maxCols = Math.floor((view.w - 2 * pad) / (font.w * sc))
      const widest = Math.max(...i.lines.map((l) => l.length))
      const lines = maxCols < widest ? balloonLines(i.lines.join(" "), Math.max(1, maxCols)) : i.lines
      const size = { w: Math.max(...lines.map((l) => l.length)) * font.w * sc + pad * 2, h: lines.length * lh + pad * 2 }
      const box = placeBox(size, i.cx * k, i.top * k - 3 * k, view, taken, lh)
      if (!box) continue
      taken.push(box)
      fill(box.x, box.y, box.w, box.h, ROLE.prose)
      if (box.y + box.h + 2 * k <= view.y + view.h) fill(box.tail - k, box.y + box.h, 2 * k, 2 * k, ROLE.prose)
      lines.forEach((l, n) => write(l, Math.round(box.x + pad), Math.round(box.y + pad + n * lh + font.ascent * sc), ROLE.fieldInk, font, sc))
    }
  }
}

let lastImageData: string | null = null

/**
 * The floor, k× by nearest neighbour with its ink drawn in, transmitted once per frame change
 * (`a=t`, image id 1) — then placed (`a=p`) cropped to the viewport on every call, so panning
 * repositions the crop without ever re-encoding or re-sending the bitmap.
 */
export function kittyImage(fr: Frame, g: Geometry, viewport: Viewport): string {
  const w = fr.width * g.k, h = fr.height * g.k
  const big = new Uint8Array(w * h * 4)
  const src = new Uint32Array(fr.rgba.buffer, fr.rgba.byteOffset, fr.width * fr.height), dst = new Uint32Array(big.buffer)
  for (let y = 0; y < h; y++) {
    const sy = Math.floor(y / g.k) * fr.width, row = y * w
    for (let x = 0; x < w; x++) dst[row + x] = src[sy + Math.floor(x / g.k)]!
  }
  inkInto(big, w, h, fr.ink, g.k, textScale(g), undefined, { x: viewport.x * g.k, y: viewport.y * g.k, w: viewport.w * g.k, h: viewport.h * g.k })
  const data = png(w, h, big).toString("base64")
  let o = ""
  if (data !== lastImageData) {
    lastImageData = data
    for (let i = 0; i < data.length; i += 4096) {
      const more = i + 4096 < data.length ? 1 : 0
      o += i === 0
        ? `${ESC}_Ga=t,f=100,i=1,q=2,m=${more};${data.slice(i, i + 4096)}${ESC}\\`
        : `${ESC}_Gm=${more};${data.slice(i, i + 4096)}${ESC}\\`
    }
  }
  const x = Math.round(viewport.x * g.k), y = Math.round(viewport.y * g.k), vw = Math.round(viewport.w * g.k), vh = Math.round(viewport.h * g.k)
  o += `${ESC}[${g.row + 1};${g.col + 1}H${ESC}_Ga=d,d=i,i=1,p=1,q=2${ESC}\\${ESC}_Ga=p,i=1,p=1,q=2,C=1,z=-1,x=${x},y=${y},w=${vw},h=${vh}${ESC}\\`
  return o
}

type Cell = { ch: string; fg?: string; bg?: string }
const hex = (r: number, g: number, b: number) => "#" + [r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")

/**
 * The room as half blocks, with the frame's ink as terminal text on the cells — where labels land on
 * the same cells, the first keeps them. One string per row, ready to write at the box's left edge.
 */
export function textLayer(fr: Frame, g: Geometry, viewport: Viewport = { x: 0, y: 0, w: g.floorW, h: g.floorH }): string[] {
  const rows0 = Math.min(g.rows, Math.ceil((viewport.h * g.k) / g.ch)), cols0 = Math.min(g.cols, Math.ceil((viewport.w * g.k) / g.cw))
  const cells: (Cell & { ink?: boolean })[][] = []
  for (let r = 0; r < rows0; r++) {
    const row: (Cell & { ink?: boolean })[] = []
    for (let c = 0; c < cols0; c++) {
      const at = (py: number) => {
        const x = Math.min(fr.width - 1, Math.floor(viewport.x + (c * g.cw) / g.k)), y = Math.min(fr.height - 1, Math.floor(viewport.y + py / g.k)), o = (y * fr.width + x) * 4
        return hex(fr.rgba[o]!, fr.rgba[o + 1]!, fr.rgba[o + 2]!)
      }
      row.push({ ch: "▀", fg: at(r * g.ch), bg: at(r * g.ch + 1) })
    }
    cells.push(row)
  }
  const put = (col: number, row: number, s: string, fg: string, bg?: string) => {
    const r = cells[row]
    if (!r || [...s].some((_, i) => r[col + i]?.ink)) return
    ;[...s].forEach((ch, i) => { const c = r[col + i]; if (c) { c.ch = ch; c.fg = fg; c.bg = bg ?? c.bg; c.ink = true } })
  }
  const toCol = (x: number) => Math.floor((x * g.k) / g.cw), toRow = (y: number) => Math.floor((y * g.k - 0.01) / g.ch)
  const taken: Box[] = []
  for (const i of fr.ink) {
    if (i.t === "text") put(i.align === "center" ? toCol(i.x) - Math.floor(i.s.length / 2) : toCol(i.x), toRow(i.y), i.s, i.color)
    else if (i.t === "brackets") {
      const c0 = toCol(i.x), c1 = toCol(i.x + i.w) - 1, r0 = toRow(i.y + 0.5), r1 = toRow(i.y + i.h)
      put(c0, r0, "┌", i.color); put(c1, r0, "┐", i.color); put(c0, r1, "└", i.color); put(c1, r1, "┘", i.color)
    } else {
      const lines = Math.max(...i.lines.map((l) => l.length)) > cols0 - 2 ? balloonLines(i.lines.join(" "), Math.max(1, cols0 - 2)) : i.lines
      const wide = Math.max(...lines.map((l) => l.length)) + 2
      const box = placeBox({ w: wide, h: lines.length }, toCol(i.cx - viewport.x), toRow(i.top - viewport.y) - 1, { x: 0, y: 0, w: cols0, h: rows0 }, taken, 1)
      if (!box) continue
      taken.push(box)
      lines.forEach((l, j) => put(box.x, box.y + j, ` ${l.padEnd(wide - 2)} `, ROLE.fieldInk, ROLE.prose))
    }
  }
  return cells.map((r) => {
    const segs: Seg[] = []
    for (const c of r) {
      const last = segs[segs.length - 1]
      if (last && last.fg === c.fg && last.bg === c.bg) last.s += c.ch
      else segs.push({ s: c.ch, fg: c.fg, bg: c.bg })
    }
    return line(segs, cols0)
  })
}

/** the topmost hit under a cell (1-based terminal coordinates), in the room's logical px */
export function hitAt(fr: Frame, g: Geometry, col: number, row: number, viewport: Viewport = { x: 0, y: 0, w: g.floorW, h: g.floorH }): Hit | undefined {
  const c = col - 1 - g.col, r = row - 1 - g.row
  if (c < 0 || r < 0 || c >= g.cols || r >= g.rows) return undefined
  const x = viewport.x + ((c + 0.5) * g.cw) / g.k, y = viewport.y + ((r + 0.5) * g.ch) / g.k
  return fr.hits.find((h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)
}
