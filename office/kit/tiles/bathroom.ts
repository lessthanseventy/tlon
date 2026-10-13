// The bathroom: its own room in the bottom-left corner, a tiled floor, a clawfoot tub with a dripping
// tap, a pedestal sink under a mirror, a towel, a toilet with the lid down — each standing apart —
// and a door onto the hallway that stands open while anyone is at it. Nina drinks from the tub's rim
// (`Sim.catDo("drink")`) and curls up in it (`Sim.catDo("tub")`, and of her own accord).
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { BATH, DOOR, doorOpen, SINK } from "../bathroom"
import { ROLE, tint } from "../palette"
import { at, type Live, type Rect, type Tile } from "../tiles"
import type { Agents } from "../types"
import { HALL, type Layout } from "../../rooms/wide"

const RIGHT = BATH.x + BATH.w, GAP = 5
/** the walls: whole along the top and down both sides, the bottom one split at the door */
export const WALLS: Rect[] = [
  { x: BATH.x, y: BATH.y, w: BATH.w, h: 2 },
  { x: BATH.x, y: BATH.y, w: 2, h: BATH.h },
  { x: RIGHT - 2, y: BATH.y, w: 2, h: BATH.h },
  { x: BATH.x, y: DOOR.y - 1, w: DOOR.x - GAP - BATH.x, h: 2 },
  { x: DOOR.x + GAP, y: DOOR.y - 1, w: RIGHT - (DOOR.x + GAP), h: 2 },
]
/** the fixtures against the back wall, left to right, with floor between each */
export const TUB: Rect = { x: 3, y: 158, w: 22, h: 11 }
export const SINK_BOX: Rect = { x: 30, y: 158, w: 9, h: 11 }
export const TOILET: Rect = { x: 45, y: 156, w: 8, h: 12 }

export function bathroomTile(): Tile<Layout> {
  let lastAt = -Infinity
  return {
    kind: "bathroom",
    blocks: () => [...WALLS, TUB, SINK_BOX, TOILET],
    spots: () => ({ bathroom: [at(SINK.x, SINK.y, HALL, "up", "bathroom")] }),
    draw(sc: Scene, _a: Agents, _l: Layout, _m: Measure, sim: Live) {
      const px = sc.px.bind(sc), f = sc.f
      const wall = ROLE.structure, enamel = ROLE.prose, shade = tint(ROLE.prose, ROLE.ground, 0.6), chrome = ROLE.inactive
      const tileA = tint(ROLE.prose, ROLE.ground, 0.34), tileB = tint(ROLE.key, ROLE.ground, 0.26), grout = tint(ROLE.prose, ROLE.ground, 0.2)

      // the floor: small checked tiles, wall to wall
      for (let y = BATH.y + 2; y < DOOR.y - 1; y += 4) for (let x = BATH.x + 2; x < RIGHT - 2; x += 4) px(x, y, 4, 4, ((x + y) / 4) % 2 ? tileA : tileB)
      // the back wall: tiled up to a ledge, so the fixtures stand against something
      px(BATH.x + 2, BATH.y + 2, BATH.w - 4, 4, tint(ROLE.key, ROLE.ground, 0.45))
      for (let x = BATH.x + 2; x < RIGHT - 2; x += 4) px(x, BATH.y + 2, 1, 4, grout)
      px(BATH.x + 2, BATH.y + 6, BATH.w - 4, 1, grout)
      // a bath mat in front of the tub
      px(TUB.x + 3, TUB.y + TUB.h + 3, 14, 4, tint(ROLE.assistant, ROLE.ground, 0.55))
      for (let x = TUB.x + 4; x < TUB.x + 17; x += 2) px(x, TUB.y + TUB.h + 7, 1, 1, tint(ROLE.assistant, ROLE.ground, 0.55))

      sc.item(BATH.y, () => px(BATH.x, BATH.y, BATH.w, 2, wall))
      sc.item(BATH.y + 1, () => { px(BATH.x, BATH.y, 2, BATH.h, wall); px(RIGHT - 2, BATH.y, 2, BATH.h, wall) })

      // the tub: its back and the basin behind her, the tap and a drip now and then …
      sc.item(TUB.y, () => {
        px(TUB.x, TUB.y, TUB.w, 2, enamel); px(TUB.x, TUB.y + 2, 1, TUB.h - 4, enamel); px(TUB.x + TUB.w - 1, TUB.y + 2, 1, TUB.h - 4, enamel)
        px(TUB.x + 1, TUB.y + 2, TUB.w - 2, TUB.h - 4, shade)
        px(TUB.x + 2, TUB.y - 3, 2, 3, chrome); px(TUB.x + 2, TUB.y - 3, 5, 1, chrome)
        if (f % 8 < 3) px(TUB.x + 6, TUB.y + 2 + (f % 8), 1, 1, ROLE.key)
      })
      // … and its rolled front lip on its claw feet, drawn after anyone lying in it
      sc.item(TUB.y + TUB.h - 0.5, () => {
        px(TUB.x, TUB.y + TUB.h - 3, TUB.w, 3, enamel); px(TUB.x + 1, TUB.y + TUB.h - 1, TUB.w - 2, 1, shade)
        for (const fx of [TUB.x + 2, TUB.x + TUB.w - 4]) px(fx, TUB.y + TUB.h, 2, 2, chrome)
      })

      // the sink on its pedestal, a tap, the mirror over it, a towel on the wall beside it
      sc.item(SINK_BOX.y + SINK_BOX.h, () => {
        const sx = SINK_BOX.x
        px(sx, SINK_BOX.y, SINK_BOX.w, 4, enamel); px(sx + 1, SINK_BOX.y + 1, SINK_BOX.w - 2, 2, shade)
        px(sx + 3, SINK_BOX.y + 4, 3, SINK_BOX.h - 4, enamel); px(sx + 3, SINK_BOX.y + 4, 1, SINK_BOX.h - 4, shade)
        px(sx + 4, SINK_BOX.y - 2, 1, 2, chrome)
      })
      sc.item(BATH.y + 2, () => {
        const mx = SINK_BOX.x + 1
        px(mx, BATH.y + 1, 7, 5, wall); px(mx + 1, BATH.y + 2, 5, 3, tint(ROLE.key, ROLE.ground, 0.6))
        if (f % 40 < 20) px(mx + 2, BATH.y + 2, 1, 1, ROLE.prose)
        px(SINK_BOX.x + SINK_BOX.w + 2, BATH.y + 3, 3, 1, chrome)
        px(SINK_BOX.x + SINK_BOX.w + 2, BATH.y + 4, 3, 6, ROLE.attention); px(SINK_BOX.x + SINK_BOX.w + 2, BATH.y + 9, 3, 1, tint(ROLE.attention, ROLE.ground, 0.6))
      })

      // the toilet: tank against the wall, the bowl with its lid down, a roll on the wall beside it
      sc.item(TOILET.y + TOILET.h, () => {
        const tx = TOILET.x
        px(tx, TOILET.y, TOILET.w, 4, enamel); px(tx + 1, TOILET.y + 1, TOILET.w - 2, 1, shade); px(tx + TOILET.w - 2, TOILET.y + 1, 1, 1, chrome)
        px(tx, TOILET.y + 4, TOILET.w, 1, shade)
        px(tx, TOILET.y + 5, TOILET.w, 4, tint(ROLE.prose, ROLE.key, 0.25)); px(tx + 1, TOILET.y + 6, TOILET.w - 2, 2, enamel)
        px(tx + 1, TOILET.y + 9, TOILET.w - 2, 2, enamel); px(tx + 2, TOILET.y + 11, TOILET.w - 4, 1, shade)
        px(tx + TOILET.w + 3, TOILET.y + 4, 2, 3, enamel); px(tx + TOILET.w + 3, TOILET.y + 4, 2, 1, chrome)
      })

      // the door: shut it is a leaf across the gap, open it swings back against the wall
      const near = [...sim.at("bathroom"), sim.cat]
      const open = doorOpen(near, sc.tick, lastAt)
      if (doorOpen(near, sc.tick, -Infinity)) lastAt = sc.tick
      sc.item(DOOR.y + 1, () => {
        for (const w of WALLS.slice(3)) px(w.x, w.y, w.w, w.h, wall)
        if (open) px(DOOR.x + GAP - 1, DOOR.y - 7, 1, 7, ROLE.borderInactive)
        else px(DOOR.x - GAP, DOOR.y - 1, GAP * 2, 2, ROLE.borderInactive)
      })
    },
  }
}
