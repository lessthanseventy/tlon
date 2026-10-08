// Home tiles as pixel art: `TILE_ART` maps a tile kind to the function that paints it, and
// `renderHome` lays the build grid out as a Frame. A new tile kind plugs in by adding a key.
import { Canvas } from "./canvas"
import type { HomeTile } from "./home"
import { ROLE, tint } from "./palette"

export const TILE = 12

/** a square sprite turned clockwise by `rot` degrees */
export function rotated(rows: string[], rot: 0 | 90 | 180 | 270 = 0): string[] {
  let r = rows
  for (let q = 0; q < rot / 90; q++) r = r.map((_, j) => r.map((_, i) => r[r.length - 1 - i]![j]!).join(""))
  return r
}

export type TileArt = (c: Canvas, x: number, y: number, tile: HomeTile) => void

/** '.' is clear (the floor shows). Colours per letter come from `PALETTES`, read at draw time. */
export const SPRITES: Record<string, string[]> = {
  living: ["............", ".rrrrrrrrrr.", ".rrrrrrrrrr.", ".rrrrrrrrrr.", ".rrrrrrrrrr.", "............",
           ".cccccccccc.", ".cccccccccc.", ".cccccccccc.", ".ccc....ccc.", "............", "...........l"],
  kitchen: ["wwwwwwwwwwww", "wssw..oo.www", "............", "............", "...tttttt...", "...tttttt...",
            "...tttttt...", "............", "............", "............", "............", "...........k"],
  bathroom: ["............", ".bbbb.......", ".bbbb.....ss", ".bbbb.....ss", ".bbbb.......", ".bbbb.......",
             "............", "............", "..pp........", "..pp........", "............", "...........m"],
  bedroom: ["............", ".pppppp.....", ".pppppp.nn..", ".qqqqqq.nn..", ".qqqqqq.....", ".qqqqqq.....",
            ".qqqqqq.....", ".qqqqqq.....", ".qqqqqq.....", "............", "............", "............"],
  street: ["kkkkkkkkkkkk", "kkkkkkkkkkkk", "eeeeeeeeeeee", "eeeeeeeeeeee", "eeeeeeeeeeee", "ddeeddeeddee",
           "eeeeeeeeeeee", "eeeeeeeeeeee", "eeeeeeeeeeee", "kkkkkkkkkkkk", "kkkkkkkkkkkk", "kkkkkkkkkkkk"],
}

const floor = () => tint(ROLE.structure, ROLE.ground, 0.3)
const PALETTES = (): Record<string, Record<string, string>> => ({
  living: { r: tint(ROLE.attention, ROLE.ground, 0.5), c: ROLE.assistant, l: ROLE.body },
  kitchen: { w: ROLE.inactive, s: ROLE.key, o: ROLE.alarm, t: ROLE.structure, k: ROLE.body },
  bathroom: { b: tint(ROLE.key, ROLE.ground, 0.6), s: ROLE.key, p: ROLE.prose, m: ROLE.body },
  bedroom: { p: ROLE.prose, q: ROLE.planner, n: ROLE.structure },
  street: { k: ROLE.borderInactive, e: ROLE.edge, d: ROLE.prose },
})

/** kind → how to paint it. A kind absent here falls back to `plainTile`; later work adds its key. */
export const TILE_ART: Record<string, TileArt> = Object.fromEntries(
  Object.keys(SPRITES).map((kind): [string, TileArt] => [kind, (c, x, y, t) => {
    c.px(x, y, TILE, TILE, floor())
    c.blit(rotated(SPRITES[kind]!, t.rot ?? 0), x, y, PALETTES()[kind]!)
  }]),
)

/** a kind with no art: a floor square with a border, so the tile is still there to see and move */
const plainTile: TileArt = (c, x, y) => {
  c.px(x, y, TILE, TILE, ROLE.meta)
  c.px(x + 1, y + 1, TILE - 2, TILE - 2, floor())
}

export function paintTile(c: Canvas, x: number, y: number, t: HomeTile) {
  (TILE_ART[t.kind] ?? plainTile)(c, x, y, t)
}
