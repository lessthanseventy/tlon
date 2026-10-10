// What a room hands a surface: its pixel art at 1x, the text and overlays to put over it, and
// where clicks land — all in the room's logical pixels. The desktop paints it with Cairo, the TUI
// with the kitty graphics protocol (or half blocks) and terminal text.
import { rgb } from "./palette"
import type { Act } from "./crew"

/** a click target, in logical pixels */
/** `note`: the thread a margin note names — hovering it lights that card (see kit/margin.ts) */
export type Hit = { x: number; y: number; w: number; h: number; tip: string; act: Act; note?: number }
/**
 * Over the art: text (`size` the font's px at the desktop's 3x — a hint; a terminal has one size),
 * the corner brackets around a picked person, and a speech balloon of a few wrapped lines.
 */
export type Ink =
  | { t: "text"; s: string; x: number; y: number; color: string; size: number; align: "center" | "left" }
  | { t: "brackets"; x: number; y: number; w: number; h: number; color: string }
  | { t: "balloon"; lines: string[]; cx: number; top: number }
export type Frame = { rgba: Uint8Array; width: number; height: number; ink: Ink[]; hits: Hit[] }
/**
 * How wide `s` is at font `size`, in logical pixels — each surface measures its own text. A surface
 * that knows its text's height says so in `lineHeight`, and a room spaces its lines by it.
 */
export type Measure = ((s: string, size: number) => number) & { lineHeight?: (size: number) => number }

/** a 1x RGBA buffer and the two ways a room paints into it */
export class Canvas {
  readonly rgba: Uint8Array
  constructor(readonly width: number, readonly height: number) { this.rgba = new Uint8Array(width * height * 4) }
  px(x: number, y: number, pw: number, ph: number, c: string) {
    const [r, g, b] = rgb(c), W = this.width, buf = this.rgba
    const x0 = Math.max(0, Math.floor(x)), x1 = Math.min(W, Math.floor(x + pw)), y1 = Math.min(this.height, Math.floor(y + ph))
    for (let j = Math.max(0, Math.floor(y)); j < y1; j++) for (let i = x0, o = (j * W + x0) * 4; i < x1; i++, o += 4) { buf[o] = r!; buf[o + 1] = g!; buf[o + 2] = b!; buf[o + 3] = 255 }
  }
  /** light falling on what is already drawn: each pixel `t` of the way toward `c` (a sunbeam, lamplight) */
  glow(x: number, y: number, pw: number, ph: number, c: string, t: number) {
    const [r, g, b] = rgb(c), W = this.width, buf = this.rgba
    const x0 = Math.max(0, Math.floor(x)), x1 = Math.min(W, Math.floor(x + pw)), y1 = Math.min(this.height, Math.floor(y + ph))
    for (let j = Math.max(0, Math.floor(y)); j < y1; j++) for (let i = x0, o = (j * W + x0) * 4; i < x1; i++, o += 4) {
      buf[o] = Math.round(buf[o]! + (r! - buf[o]!) * t); buf[o + 1] = Math.round(buf[o + 1]! + (g! - buf[o + 1]!) * t); buf[o + 2] = Math.round(buf[o + 2]! + (b! - buf[o + 2]!) * t)
    }
  }
  /** a sprite: one char per pixel, "." (or any char `map` lacks) clear */
  blit(rows: string[], x: number, y: number, map: Record<string, string>) {
    rows.forEach((row, j) => { for (let i = 0; i < row.length; i++) { const c = map[row[i]!]; if (c) this.px(x + i, y + j, 1, 1, c) } })
  }
}

/** a name cut to `w` logical px at `size` */
export function fit(measure: Measure, name: string, w: number, size: number) {
  let n = name
  while (n.length > 2 && measure(n, size) > w) n = n.slice(0, -1)
  return n === name ? name : `${n.slice(0, -1)}.`
}
/** what someone said, as a balloon's few lines: ASCII (a toy font has no fallback), 34x4 by default, a word longer than a line hard-broken */
export function balloonLines(said: string, width = 34, rows = 4): string[] {
  const flat = said.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, "-").replace(/…/g, "...")
    .replace(/[^\x20-\x7e]/g, "").replace(/\s+/g, " ").trim()
  const lines: string[] = []
  let line = ""
  for (let w of flat.split(" ").filter(Boolean)) {
    while (w.length > width) {
      if (line) { lines.push(line); line = "" }
      lines.push(w.slice(0, width)); w = w.slice(width)
    }
    if (line && line.length + 1 + w.length > width) { lines.push(line); line = w } else line = line ? `${line} ${w}` : w
  }
  if (line) lines.push(line)
  if (lines.length <= rows) return lines
  const kept = lines.slice(0, rows)
  kept[rows - 1] = kept[rows - 1]!.slice(0, Math.max(0, width - 3)).trimEnd() + "..."
  return kept
}
