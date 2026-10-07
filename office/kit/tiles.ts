// A tile is a room module: its footprints, its spots, and how to draw it, in absolute room
// coordinates for this step (no grid offset yet — see spec, "non-goals"). floorPlan composes a
// list of them into the Plan the sim needs.
import type { Measure } from "./canvas"
import type { Scene } from "./draw"
import type { Actor, CatPlan, Kind, Pastime, Pt, Spot } from "./sim"
import type { Agents } from "./types"

export type TileKind = "office" | "cat-corner" | "meeting" | "lounge" | "kitchen" | "games"
export type Rect = { x: number; y: number; w: number; h: number }

/** the live sim state a tile's draw reads at paint time, beyond the snapshot and its own layout */
export type Live = {
  /** who is settled at a pastime of this kind, and where */
  at(kind: Kind | Pastime): Actor[]
  /** someone there now, mid-walk-up included (coffee at the machine starts the moment they arrive) */
  using(kind: Kind | Pastime): boolean
  /** Nina's position, for a tile whose art reacts to her (the aquarium's fish gathering at the glass) */
  cat: Pt
}

export type Tile<L> = {
  kind: TileKind
  /** this tile's footprints, for the route test and the walk */
  blocks(l: L): Rect[]
  /** this tile's spots, by kind — unioned across every tile on the floor */
  spots(l: L): Partial<Record<Kind | Pastime, Spot[]>>
  /** this tile's slice of Nina's places, if it has one (only `cat-corner` does, this step) */
  cat?(l: L): Partial<CatPlan>
  /** art + furniture, at the scene's draw time */
  draw(sc: Scene, a: Agents, l: L, m: Measure, sim: Live): void
}

export type Home = { tiles: { kind: TileKind; at: [number, number] }[] }

/** a place to be, at absolute room coordinates: the one spot-builder every tile's `spots()` uses */
export function at(x: number, y: number, aisle: number, face: Spot["face"], kind: Spot["kind"], partner?: Pt): Spot {
  return { x, y, aisle, pose: "stand", face, kind, ...(partner ? { with: partner } : {}) }
}
