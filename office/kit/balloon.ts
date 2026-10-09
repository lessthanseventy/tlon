export type Box = { x: number; y: number; w: number; h: number }

const hit = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

/** place one balloon: box centred on `cx`, bottom at `bottom`, clamped inside `area`, nudged up by `gap` steps off `taken`; null = no room (the balloon waits a frame) */
export function placeBox(size: { w: number; h: number }, cx: number, bottom: number, area: Box, taken: Box[], gap: number): (Box & { tail: number }) | null {
  if (size.w > area.w || size.h > area.h) return null
  const x = Math.min(Math.max(cx - size.w / 2, area.x), area.x + area.w - size.w)
  for (let y = Math.min(Math.max(area.y, bottom - size.h), area.y + area.h - size.h); y >= area.y; y -= gap) {
    const box = { x, y, w: size.w, h: size.h }
    if (taken.some((t) => hit(box, t))) continue
    const inset = Math.min(gap, size.w / 2)
    return { ...box, tail: Math.min(Math.max(cx, x + inset), x + size.w - inset) }
  }
  return null
}
