// A tile is a room module: its footprints, its spots, and how to draw it, in absolute room
// coordinates for this step (no grid offset yet — see spec, "non-goals"). floorPlan composes a
// list of them into the Plan the sim needs.
import type { Measure } from "./canvas"
import type { Focus, Scene } from "./draw"
import type { Actor, Cat, CatPlan, Kind, Pastime, Pt, Spot } from "./sim"
import type { Agents } from "./types"

export type TileKind = "office" | "cat-corner" | "meeting" | "lounge" | "kitchen" | "games"
export type Rect = { x: number; y: number; w: number; h: number }

/** the live sim state a tile's draw reads at paint time, beyond the snapshot and its own layout */
export type Live = {
  /** who is settled at a pastime of this kind, and where */
  at(kind: Kind | Pastime): Actor[]
  /** someone there now, mid-walk-up included (coffee at the machine starts the moment they arrive) */
  using(kind: Kind | Pastime): boolean
  /** Nina, for a tile whose art reacts to her (the aquarium's fish gathering at the glass, her corner's yarn) */
  cat: Cat
  /** the actor seated at a desk/chair owned by this agent, if any is on the clock right now */
  actor(agent: string): Actor | undefined
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
  draw(sc: Scene, a: Agents, l: L, m: Measure, sim: Live, focus: Focus): void
}

export type Home = { tiles: { kind: TileKind; at: [number, number] }[] }

/** today's office, tile for tile — the compiled-in default until a real `home.json` is read */
export const DEFAULT_OFFICE: Home = {
  // lounge before office: both have a "plant" spot, and the lounge's comes first in the original
  // array this replaces — tile order breaks that tie for any kind more than one tile contributes.
  tiles: [
    { kind: "lounge", at: [0, 0] }, { kind: "office", at: [0, 0] }, { kind: "cat-corner", at: [0, 0] },
    { kind: "meeting", at: [0, 0] }, { kind: "kitchen", at: [0, 0] }, { kind: "games", at: [0, 0] },
  ],
}

/** a place to be, at absolute room coordinates: the one spot-builder every tile's `spots()` uses */
export function at(x: number, y: number, aisle: number, face: Spot["face"], kind: Spot["kind"], partner?: Pt): Spot {
  return { x, y, aisle, pose: "stand", face, kind, ...(partner ? { with: partner } : {}) }
}
