// A tile is a room module: its footprints, its spots, and how to draw it, in absolute room
// coordinates for this step (no grid offset yet — see spec, "non-goals"). floorPlan composes a
// list of them into the Plan the sim needs.
import type { Measure } from "./canvas"
import type { Scene } from "./draw"
import type { CatPlan, Kind, Pastime, Spot } from "./sim"
import type { Agents } from "./types"

export type TileKind = "office" | "cat-corner" | "meeting" | "lounge" | "kitchen" | "games"
export type Rect = { x: number; y: number; w: number; h: number }

export type Tile<L> = {
  kind: TileKind
  /** this tile's footprints, for the route test and the walk */
  blocks(l: L): Rect[]
  /** this tile's spots, by kind — unioned across every tile on the floor */
  spots(l: L): Partial<Record<Kind | Pastime, Spot[]>>
  /** this tile's slice of Nina's places, if it has one (only `cat-corner` does, this step) */
  cat?(l: L): Partial<CatPlan>
  /** art + furniture, at the scene's draw time */
  draw(sc: Scene, a: Agents, l: L, m: Measure): void
}

export type Home = { tiles: { kind: TileKind; at: [number, number] }[] }
