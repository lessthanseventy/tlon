// Nina's corner of the office: her tower, the litter box, the yarn and a mouse on the rug, the
// radiator she suns herself on — and all of her CatPlan (this step doesn't split it any finer).
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { ROLE, tint } from "../palette"
import type { Rect, Tile } from "../tiles"
import type { CatPlan, Pt } from "../sim"
import type { Agents } from "../types"
import { fishWatch, HALL, OFF_LANE, OFF_W, corner, type Layout, type Zones } from "../../rooms/wide"

const TOWER_X = 78, PERCH_TOP = { x: 83, y: 52 }, PERCH_MID = { x: 83, y: 69 }
const CAT_NAP = { x: 50, y: 128 }, CAT_DESK = { x: 37, y: 75 }, LITTER = { x: 7, y: 98 }, PLAY = { x: 70, y: 132 }
const YARN = { x: 76, y: 130 }, MOUSE = { x: 24, y: 134 }
const RADIATOR = { x: 2, y: 116, w: 10, h: 12 }, CAT_WARM = { x: 7, y: 115 }

export { CAT_DESK, CAT_WARM, PERCH_TOP, RADIATOR, TOWER_X }

export function catCornerTile(z: Zones): Tile<Layout> & { cat(): CatPlan } {
  const { L0, W: w } = z
  const { shelf } = corner(z)
  const inOffice = (x: number) => x <= OFF_W

  return {
    kind: "cat-corner",
    blocks: (): Rect[] => [{ x: TOWER_X, y: 40, w: 12, h: 48 }, RADIATOR],
    spots: () => ({}),
    cat: (): CatPlan => ({
      nap: CAT_NAP, desk: CAT_DESK, play: PLAY, litter: LITTER, perches: [PERCH_TOP, PERCH_MID], warm: CAT_WARM,
      // the zoomies: your office (your desk, her tower) and the lounge (the couch back, the top of
      // the TV, the kitchen counter), each first the floor spot she lands on after
      leaps: [
        [CAT_NAP, CAT_DESK, PERCH_TOP, PERCH_MID, { x: 18, y: 112 }, { x: 72, y: 142 }],
        [{ x: L0 + 52, y: 104 }, { x: L0 + 46, y: 69 }, { x: L0 + 80, y: 69 }, { x: L0 + 58, y: 7 }, { x: w - 7, y: 99 }, { x: L0 + 100, y: 140 }],
      ],
      // the armchair too, when it's empty: a princess takes the good seat
      lounge: [{ x: L0 + 52, y: 104 }, { x: w - 40, y: 126 }, { x: shelf.x + 8, y: 82 }],
      spots: [CAT_NAP, { x: 24, y: 140 }, { x: 40, y: 104 }, CAT_DESK, PERCH_TOP, PERCH_MID, PLAY, { x: L0 + 52, y: 104 }, fishWatch(z)],
      via: (p: Pt) =>
        p.x === CAT_DESK.x && p.y === CAT_DESK.y ? { x: CAT_DESK.x, y: 100 }
          : p.x === PERCH_TOP.x && p.y <= PERCH_MID.y ? { x: PERCH_TOP.x, y: 94 }
            : p.x === LITTER.x && p.y === LITTER.y ? { x: LITTER.x, y: 106 }
              : p.x === CAT_WARM.x && p.y === CAT_WARM.y ? { x: CAT_WARM.x, y: 136 } : null,
      // out of one room and into another along the hallway: your office by its door, the lounge by
      // its lane, the open floor by the column she watches the fish from
      door: (from, to) => {
        const roomOf = (p: Pt) => (inOffice(p.x) ? "office" : p.x >= L0 ? "lounge" : "floor")
        const a = roomOf(from), b = roomOf(to), fx = fishWatch(z).x
        if (a === b) return []
        const out = { office: [{ x: OFF_LANE, y: 160 }, { x: OFF_LANE, y: HALL - 3 }], lounge: [{ x: L0 + 6, y: HALL - 3 }], floor: [{ x: fx, y: HALL - 3 }] }
        const into = { office: [{ x: OFF_LANE, y: HALL - 3 }, { x: OFF_LANE, y: 160 }], lounge: [{ x: L0 + 6, y: HALL - 3 }, { x: L0 + 6, y: to.y }], floor: [{ x: fx, y: HALL - 3 }] }
        return [...out[a], ...into[b]]
      },
    }),
    draw(sc: Scene, a: Agents, _l: Layout, _m: Measure, sim) {
      const c = sim.cat, px = sc.px.bind(sc), f = sc.f
      sc.item(88, () => {
        const tx = TOWER_X, carpet = ROLE.meta, under = tint(ROLE.meta, ROLE.ground, 0.5)
        px(tx + 4, 54, 3, 32, ROLE.inactive); for (let y = 56; y < 84; y += 3) px(tx + 4, y, 3, 1, ROLE.borderInactive)
        px(tx, 84, 11, 3, carpet); px(tx, 87, 11, 1, under)
        px(tx, 69, 11, 2, carpet); px(tx, 71, 11, 1, under)
        px(tx - 1, 52, 12, 2, carpet); px(tx - 1, 54, 12, 1, under)
        px(tx + 10, 71, 1, 5, ROLE.prose); px(tx + 9, 76, 3, 2, ROLE.attention)
      })
      sc.item(92, () => { px(1, 93, 10, 4, ROLE.key); px(2, 94, 8, 2, ROLE.inactive) })
      sc.item(100, () => px(1, 97, 10, 2, ROLE.key))
      sc.item(YARN.y, () => {
        const yx = YARN.x + (c.mode === "play" ? [0, 1, 2, 1][c.yarn]! : 0)
        px(yx, YARN.y - 3, 3, 3, ROLE.attention); px(yx + 1, YARN.y - 2, 1, 1, ROLE.assistant); px(yx - 2, YARN.y - 1, 2, 1, ROLE.attention)
      })
      sc.item(MOUSE.y, () => { px(MOUSE.x, MOUSE.y - 2, 4, 2, ROLE.prose); px(MOUSE.x + 3, MOUSE.y - 3, 1, 1, ROLE.attention); px(MOUSE.x - 2, MOUSE.y - 1, 2, 1, ROLE.attention) })
      // the radiator, and on a cold day the heat shimmering off it
      sc.item(RADIATOR.y + RADIATOR.h, () => {
        px(RADIATOR.x, RADIATOR.y, RADIATOR.w, RADIATOR.h, ROLE.prose)
        for (let k = 1; k < RADIATOR.w; k += 2) px(RADIATOR.x + k, RADIATOR.y + 1, 1, RADIATOR.h - 2, tint(ROLE.prose, ROLE.ground, 0.6))
        if ((a.weather?.temp_c ?? 20) < 10) for (let k = 0; k < 3; k++) px(RADIATOR.x + 2 + k * 3 + ((f + k) % 2), RADIATOR.y - 3 - ((f + k) % 3), 1, 2, tint(ROLE.alarm, ROLE.ground, 0.5))
      })
    },
  }
}
