// The bathroom off the hall: a tub with a dripping tap, a sink, a toilet with the lid down, and a
// door that stands open while anyone is at it. Nina drinks from the tub (`Sim.catDo("drink")`).
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { BATH, DOOR, doorOpen, RIM, SINK } from "../bathroom"
import { ROLE, tint } from "../palette"
import { at, type Live, type Rect, type Tile } from "../tiles"
import type { Agents } from "../types"
import { HALL, type Layout } from "../../rooms/wide"

/** the walls: the bottom one split at the door */
export const WALLS: Rect[] = [
  { x: BATH.x, y: BATH.y, w: BATH.w, h: 2 },
  { x: BATH.x, y: BATH.y, w: 2, h: BATH.h },
  { x: BATH.x + BATH.w - 2, y: BATH.y, w: 2, h: BATH.h },
  { x: BATH.x, y: DOOR.y - 1, w: DOOR.x - 5 - BATH.x, h: 2 },
  { x: DOOR.x + 5, y: DOOR.y - 1, w: BATH.x + BATH.w - (DOOR.x + 5), h: 2 },
]
export const TUB: Rect = { x: 26, y: 156, w: 30, h: 14 }
const SINK_BOX: Rect = { x: 60, y: 155, w: 12, h: 8 }, TOILET: Rect = { x: 72, y: 164, w: 7, h: 8 }

export function bathroomTile(): Tile<Layout> {
  let lastAt = -Infinity
  return {
    kind: "bathroom",
    blocks: () => [...WALLS, TUB, SINK_BOX, TOILET],
    spots: () => ({ bathroom: [at(SINK.x, SINK.y, HALL, "up", "bathroom")] }),
    draw(sc: Scene, _a: Agents, _l: Layout, _m: Measure, sim: Live) {
      const px = sc.px.bind(sc), f = sc.f
      const wall = ROLE.structure, enamel = ROLE.prose, shade = tint(ROLE.prose, ROLE.ground, 0.6)
      px(BATH.x, BATH.y, BATH.w, BATH.h, tint(ROLE.structure, ROLE.ground, 0.15))
      for (let y = BATH.y + 4; y < DOOR.y - 1; y += 4) for (let x = BATH.x + 2 + ((y >> 2) % 2) * 4; x < BATH.x + BATH.w - 2; x += 8) px(x, y, 1, 1, tint(ROLE.structure, ROLE.ground, 0.3))
      sc.item(BATH.y, () => px(BATH.x, BATH.y, BATH.w, 2, wall))
      sc.item(BATH.y + 1, () => { px(BATH.x, BATH.y, 2, BATH.h, wall); px(BATH.x + BATH.w - 2, BATH.y, 2, BATH.h, wall) })
      // the tub, a rim to sit on, the tap and a drip falling now and then
      sc.item(RIM.y - 1, () => {
        px(TUB.x, TUB.y, TUB.w, TUB.h, enamel); px(TUB.x + 1, TUB.y + 2, TUB.w - 2, TUB.h - 4, shade)
        px(TUB.x + 3, TUB.y + TUB.h, 2, 2, ROLE.inactive); px(TUB.x + TUB.w - 5, TUB.y + TUB.h, 2, 2, ROLE.inactive)
        px(TUB.x + 4, TUB.y - 3, 2, 3, ROLE.inactive); px(TUB.x + 4, TUB.y - 3, 4, 1, ROLE.inactive)
        if (f % 8 < 3) px(TUB.x + 7, TUB.y + 1 + (f % 8), 1, 1, ROLE.key)
      })
      sc.item(SINK_BOX.y + SINK_BOX.h, () => {
        px(SINK_BOX.x, SINK_BOX.y, SINK_BOX.w, SINK_BOX.h, enamel); px(SINK_BOX.x + 2, SINK_BOX.y + 2, SINK_BOX.w - 4, 3, shade)
        px(SINK_BOX.x + 5, SINK_BOX.y - 2, 2, 2, ROLE.inactive)
      })
      sc.item(TOILET.y + TOILET.h, () => {
        px(TOILET.x, TOILET.y, TOILET.w, TOILET.h, enamel); px(TOILET.x + 1, TOILET.y + 1, TOILET.w - 2, 4, tint(ROLE.prose, ROLE.key, 0.3))
        px(TOILET.x, TOILET.y - 3, TOILET.w, 3, enamel)
      })
      // the door: shut it is a leaf across the gap, open it swings back against the wall
      const near = [...sim.at("bathroom"), sim.cat]
      const open = doorOpen(near, sc.tick, lastAt)
      if (doorOpen(near, sc.tick, -Infinity)) lastAt = sc.tick
      sc.item(DOOR.y + 1, () => {
        for (const w of WALLS.slice(3)) px(w.x, w.y, w.w, w.h, wall)
        if (open) px(DOOR.x + 4, DOOR.y - 6, 1, 6, ROLE.borderInactive)
        else px(DOOR.x - 5, DOOR.y - 1, 10, 2, ROLE.borderInactive)
      })
    },
  }
}
