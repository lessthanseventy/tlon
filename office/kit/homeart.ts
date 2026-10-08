// Home tiles as pixel art: `TILE_ART` maps a tile kind to the function that paints it, and
// `renderHome` lays the build grid out as a Frame. A new tile kind plugs in by adding a key.
import { Canvas, type Frame } from "./canvas"
import { gridWindow, type Home, type HomeTile, type Pt } from "./home"
import { ROLE, tint } from "./palette"

export const TILE = 12
const CELL = TILE + 2

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
  garden: ["f.f.f.f.f.f.", "ffffffffffff", "............", ".gg.gg.gg.gg", ".gg.gg.gg.gg", "............",
           ".dd.dd.dd.dd", ".dd.dd.dd.dd", "............", "..ll.....ll.", "............", "............"],
}

const floor = () => tint(ROLE.structure, ROLE.ground, 0.3)
const PALETTES = (): Record<string, Record<string, string>> => ({
  living: { r: tint(ROLE.attention, ROLE.ground, 0.5), c: ROLE.assistant, l: ROLE.body },
  kitchen: { w: ROLE.inactive, s: ROLE.key, o: ROLE.alarm, t: ROLE.structure, k: ROLE.body },
  bathroom: { b: tint(ROLE.key, ROLE.ground, 0.6), s: ROLE.key, p: ROLE.prose, m: ROLE.body },
  bedroom: { p: ROLE.prose, q: ROLE.planner, n: ROLE.structure },
  street: { k: ROLE.borderInactive, e: ROLE.edge, d: ROLE.prose },
  garden: { f: ROLE.structure, g: ROLE.live, d: ROLE.borderInactive, l: ROLE.attention },
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

export const ANNEX_PAD = 8
const bounds = (h: Home) => ({ x0: Math.min(...h.tiles.map((t) => t.at[0])), y0: Math.min(...h.tiles.map((t) => t.at[1])), y1: Math.max(...h.tiles.map((t) => t.at[1])) })

/** px height of the strip that shows `h` under the office: 0 when it has no tiles */
export const annexHeight = (h: Home) => h.tiles.length ? (bounds(h).y1 - bounds(h).y0 + 1) * CELL + 2 * ANNEX_PAD : 0

/** paints the home on `c` from row `y`: ground, then every tile via `paintTile`. Canvas clips what overruns the width. */
export function paintAnnex(c: Canvas, h: Home, y: number) {
  if (!h.tiles.length) return
  const { x0, y0 } = bounds(h)
  c.px(0, y, c.width, annexHeight(h), ROLE.ground)
  for (const t of h.tiles) paintTile(c, ANNEX_PAD + (t.at[0] - x0) * CELL + 1, y + ANNEX_PAD + (t.at[1] - y0) * CELL + 1, t)
}

export type HomeView = { home: Home; cursor: Pt; carrying: HomeTile | null; refused: boolean; w: number; h: number }

/** the build grid as a Frame of w×h logical px: every cell of `gridWindow`, centred; no text, no hits */
export function renderHome({ home, cursor, carrying, refused, w, h }: HomeView): Frame {
  const c = new Canvas(w, h)
  c.px(0, 0, w, h, ROLE.ground)
  const win = gridWindow(home, cursor)
  const ox = Math.floor((w - (win.x1 - win.x0 + 1) * CELL) / 2), oy = Math.floor((h - (win.y1 - win.y0 + 1) * CELL) / 2)
  const pos = ([x, y]: Pt): Pt => [ox + (x - win.x0) * CELL + 1, oy + (y - win.y0) * CELL + 1]
  for (let y = win.y0; y <= win.y1; y++) for (let x = win.x0; x <= win.x1; x++) {
    const [px, py] = pos([x, y])
    const t = home.tiles.find((q) => q.at[0] === x && q.at[1] === y)
    if (t) paintTile(c, px, py, t)
    else c.px(px, py, TILE, TILE, ROLE.raised)
  }
  const [cx, cy] = pos(cursor)
  if (carrying) {
    paintTile(c, cx, cy, { ...carrying, at: cursor })
    c.glow(cx, cy, TILE, TILE, ROLE.ground, 0.45)
  }
  return { rgba: c.rgba, width: w, height: h, hits: [],
    ink: [{ t: "brackets", x: cx - 1, y: cy - 1, w: TILE + 2, h: TILE + 2, color: refused ? ROLE.alarm : ROLE.attention }] }
}
