// A viewport over a floor bigger than the terminal: a window in logical px, clamped to the
// floor's bounds, that pans on keys or a drag instead of the room ever being asked to fit.
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
