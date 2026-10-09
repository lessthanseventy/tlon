// Builds the Plan the sim needs by unioning every tile on the floor. For this step every tile is
// anchored at [0,0] (absolute coordinates); the grid offset in `home.tiles[].at` is read but not
// yet applied — step 3 (build mode) applies it.
import type { Actor, Kind, Pastime, Plan, Spot } from "./sim"
import type { Home, Rect, Tile, TileKind } from "./tiles"
import { EMPTY } from "./types"
import { catCornerTile } from "./tiles/cat-corner"
import { gamesTile } from "./tiles/games"
import { kitchenTile } from "./tiles/kitchen"
import { loungeTile } from "./tiles/lounge"
import { meetingTile } from "./tiles/meeting"
import { officeTile } from "./tiles/office"
import { BAND, HALL, laneOf, layoutFor, SEAT_GAP, zones, type Layout, type Zones } from "../rooms/wide"

const FACTORIES: Record<TileKind, (z: Zones, w: number) => Tile<Layout>> = {
  office: officeTile, "cat-corner": catCornerTile, meeting: meetingTile,
  lounge: loungeTile, kitchen: kitchenTile, games: gamesTile,
}

/** every spot kind that belongs in the Plan's flat `lounge` array — a worker idling, not queued */
const LOUNGE_KINDS: (Kind | Pastime)[] = [
  "couch", "cooler", "coffee", "arcade", "pingpong", "aquarium", "window", "plant", "chat", "pet", "vending", "foosball", "pool", "read",
]

export function floorPlan(home: Home, w: number): Plan<Layout> & { blocks: (l: Layout) => Rect[] } {
  const z = zones(w)
  const tiles = home.tiles.map((t) => FACTORIES[t.kind](z, w))
  const office = officeTile(z)
  const nina = catCornerTile(z)
  const l0 = layoutFor(z)(EMPTY)
  return {
    layout: layoutFor(z),
    home: office.home,
    // whoever has a question for you stands in front of your desk; the rest wait behind them
    queue: tiles.flatMap((t) => t.spots(l0).queue ?? []),
    // by kind, not by tile: idle-target order is load-bearing (sim.ts picks the first free spot), so
    // this reproduces the exact kind sequence the room drew its spots in before the cut
    lounge: LOUNGE_KINDS.flatMap((k) => tiles.flatMap((t) => t.spots(l0)[k] ?? [])),
    exit: { x: w - 3, y: HALL, aisle: HALL, pose: "stand", face: "right", kind: "exit" },
    muster: Array.from({ length: 16 }, (_, i) => ({
      x: w - 8 - (i % 4) * 9, y: HALL - 2 - Math.floor(i / 4) * 5, aisle: HALL, pose: "stand" as const, face: "down" as const, kind: "exit" as const,
    })),
    pen: { x: z.F1 - 30, y: 51, aisle: 51, pose: "stand", face: "up", kind: "note" },
    // under the suggestion box on the wall between the notes board and the windows
    box: { x: z.F1 + 1, y: 51, aisle: 51, pose: "stand", face: "up", kind: "note" },
    /** beside whoever is visited: in front of a desk that faces the room, beside a seat at a table, else where they stand */
    visit(h: Actor): Spot {
      const at = h.spot.kind === "desk" && !h.path.length
      if (at && h.spot.face === "down") return { x: h.x, y: h.spot.y + 16, aisle: h.spot.y + 16, pose: "stand", face: "up", kind: "visit" }
      if (at) return { x: h.x + SEAT_GAP / 2, y: h.spot.y, aisle: h.spot.aisle, pose: "stand", face: "left", kind: "visit" }
      return { x: Math.min(w - 10, h.x + 12), y: h.y, aisle: h.y, pose: "stand", face: "left", kind: "visit" }
    },
    // the lounge is full: a stroll along the floor's back aisle
    roam: () => ({ x: z.F0 + 10 + Math.floor(Math.random() * Math.max(1, z.F1 - z.F0 - 20)), y: 176, aisle: 176, pose: "stand", face: "down", kind: "roam" }),
    route(x, from, goal) {
      const la = laneOf(z, x), lb = laneOf(z, goal.x)
      const there = [{ x: lb, y: goal.aisle }, { x: goal.x, y: goal.aisle }, { x: goal.x, y: goal.y }]
      if (la === lb) return [{ x, y: from }, { x: la, y: from }, ...there]
      return [{ x, y: from }, { x: la, y: from }, { x: la, y: HALL }, { x: lb, y: HALL }, ...there]
    },
    cat: nina.cat(),
    blocks(l: Layout): Rect[] {
      return [{ x: 0, y: 0, w, h: BAND }, ...tiles.flatMap((t) => t.blocks(l))]
    },
  }
}
