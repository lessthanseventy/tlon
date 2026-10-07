// pixel RGBA → the nearest char in a figure's paint map (Lab distance).
// Pure: no PNG decoding here (office/cli.ts owns that) so this stays reachable from the TUI build.
function srgbToLinear(c: number) { const s = c / 255; return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4 }
function hexToLab(hex: string): [number, number, number] {
  const r = srgbToLinear(parseInt(hex.slice(1, 3), 16)), g = srgbToLinear(parseInt(hex.slice(3, 5), 16)), b = srgbToLinear(parseInt(hex.slice(5, 7), 16))
  const x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047, y = r * 0.2126 + g * 0.7152 + b * 0.0722, z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
  const f = (t: number) => (t > 0.008856 ? Math.cbrt(t) : (903.3 * t + 16) / 116)
  const fx = f(x), fy = f(y), fz = f(z)
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
}
/** the char in `paint` ("#f00" etc. hex values) nearest `hex` by Lab distance; alpha below `cut` (0-255) → "." */
export function nearestChar(hex: string, paint: Record<string, string>, alpha = 255, cut = 128): string {
  if (alpha < cut) return "."
  const [L, a, b] = hexToLab(hex)
  let best = "", bestD = Infinity
  for (const [ch, h] of Object.entries(paint)) {
    const [L2, a2, b2] = hexToLab(h), d = (L - L2) ** 2 + (a - a2) ** 2 + (b - b2) ** 2
    if (d < bestD) { bestD = d; best = ch }
  }
  return best
}
