// Home tiles as pixel art: `TILE_ART` maps a tile kind to the function that paints it, and
// `renderHome` lays the build grid out as a Frame. A new tile kind plugs in by adding a key.

/** a square sprite turned clockwise by `rot` degrees */
export function rotated(rows: string[], rot: 0 | 90 | 180 | 270 = 0): string[] {
  let r = rows
  for (let q = 0; q < rot / 90; q++) r = r.map((_, j) => r.map((_, i) => r[r.length - 1 - i]![j]!).join(""))
  return r
}
