// A viewport over a floor bigger than the terminal: a window in logical px, clamped to the
// floor's bounds, that pans on keys or a drag instead of the room ever being asked to fit.
import type { Frame, Ink } from "../kit/canvas"
import { ROLE } from "../kit/palette"

export type Viewport = { x: number; y: number; w: number; h: number }

export function clampViewport(v: Viewport, floorW: number, floorH: number): Viewport {
  const x = v.w >= floorW ? 0 : Math.max(0, Math.min(v.x, floorW - v.w))
  const y = v.h >= floorH ? 0 : Math.max(0, Math.min(v.y, floorH - v.h))
  return { ...v, x, y }
}

export function panViewport(v: Viewport, dx: number, dy: number, floorW: number, floorH: number): Viewport {
  return clampViewport({ ...v, x: v.x + dx, y: v.y + dy }, floorW, floorH)
}

/** a viewport centred on a point, clamped to the floor */
export function centerViewport(v: Viewport, cx: number, cy: number, floorW: number, floorH: number): Viewport {
  return clampViewport({ ...v, x: cx - v.w / 2, y: cy - v.h / 2 }, floorW, floorH)
}

/** the one glyph that points toward a point fallen outside the viewport, and where on its edge to put it */
function edgeMarker(x: number, y: number, v: Viewport): { glyph: string; x: number; y: number } | null {
  const out = (["left", "right", "up", "down"] as const)
    .map((dir) => [dir, dir === "left" ? v.x - x : dir === "right" ? x - (v.x + v.w) : dir === "up" ? v.y - y : y - (v.y + v.h)] as const)
    .filter(([, d]) => d > 0)
    .sort((a, b) => b[1] - a[1])
  const dir = out[0]?.[0]
  if (!dir) return null
  const mx = dir === "left" ? v.x : dir === "right" ? v.x + v.w : Math.min(Math.max(x, v.x), v.x + v.w)
  const my = dir === "up" ? v.y : dir === "down" ? v.y + v.h : Math.min(Math.max(y, v.y), v.y + v.h)
  const glyph = dir === "left" ? "◂" : dir === "right" ? "▸" : dir === "up" ? "▴" : "▾"
  return { glyph, x: mx, y: my }
}

/** drops a `Hit` the viewport can't see, and a `text`/`balloon` falling outside it becomes a
 * one-glyph edge marker pointing toward where it went; `brackets` likewise vanish off-screen */
export function clipFrame(fr: Frame, v: Viewport): Frame {
  const inside = (x: number, y: number) => x >= v.x && x <= v.x + v.w && y >= v.y && y <= v.y + v.h
  const hits = fr.hits.filter((h) => h.x + h.w > v.x && h.x < v.x + v.w && h.y + h.h > v.y && h.y < v.y + v.h)
  const ink: Ink[] = fr.ink.flatMap((i): Ink[] => {
    if (i.t === "text") {
      if (inside(i.x, i.y)) return [i]
      const m = edgeMarker(i.x, i.y, v)
      return m ? [{ ...i, s: `${m.glyph} ${i.s}`, x: m.x, y: m.y, align: "left" }] : []
    }
    if (i.t === "brackets") return inside(i.x + i.w / 2, i.y + i.h / 2) ? [i] : []
    if (inside(i.cx, i.top)) return [i]
    const m = edgeMarker(i.cx, i.top, v)
    return m ? [{ t: "text", s: `${m.glyph} ${i.lines[0] ?? ""}`, x: m.x, y: m.y, color: ROLE.fieldInk, size: 11, align: "left" }] : []
  })
  return { ...fr, ink, hits }
}
