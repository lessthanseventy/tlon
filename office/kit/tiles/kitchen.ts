// The kitchen: the cooler, the coffee machine, the snack machine, the counter and fridge.
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { ROLE, tint } from "../palette"
import { at, type Live, type Rect, type Tile } from "../tiles"
import type { Agents } from "../types"
import { COFFEE, COOLER } from "../sprites"
import { corner, type Layout, type Zones } from "../../rooms/wide"

export function kitchenTile(z: Zones, w: number): Tile<Layout> {
  const { vending: v } = corner(z)
  const counter: Rect = { x: w - 14, y: 100, w: 14, h: 56 }

  return {
    kind: "kitchen",
    blocks: () => [counter, v],
    spots: () => ({
      cooler: [at(w - 26, 116, 116, "right", "cooler")],
      coffee: [at(w - 26, 136, 136, "right", "coffee")],
      vending: [at(v.x + 6, 80, 94, "up", "vending")],
    }),
    draw(sc: Scene, a: Agents, _l: Layout, _m: Measure, sim: Live) {
      const f = sc.f, tick = sc.tick, px = sc.px.bind(sc), blit = sc.blit.bind(sc)
      sc.item(156, () => {
        px(w - 14, 100, 14, 56, ROLE.structure); px(w - 14, 100, 14, 2, ROLE.borderInactive)
        blit(COOLER, w - 12, 98, { k: ROLE.key, m: ROLE.prose, a: ROLE.alarm, o: ROLE.inactive })
        blit(COFFEE, w - 11, 128, { m: ROLE.inactive, l: ROLE.live, c: ROLE.prose })
        if (sim.using("coffee")) blit(f % 2 ? ["v.v", ".v."] : [".v.", "v.v"], w - 9, 125, { v: ROLE.prose })
        px(w - 13, 140, 12, 15, ROLE.prose); px(w - 3, 145, 1, 4, ROLE.inactive) // the fridge
        if (a.celebrations?.length) {
          // the cake on the counter, its candle flickering
          px(w - 11, 104, 8, 4, ROLE.alarm); px(w - 11, 104, 8, 1, ROLE.prose); px(w - 8, 101, 1, 3, ROLE.key); px(w - 8, 100, 1, 1, f % 2 ? ROLE.attention : ROLE.alarm)
        }
      })
      sc.item(v.y + v.h, () => {
        // the snack machine: rows of snacks behind the glass, a can thunking down when someone buys
        px(v.x, v.y, v.w, v.h, ROLE.alarm); px(v.x + 1, v.y + 2, 7, 16, tint(ROLE.prose, ROLE.ground, 0.3))
        for (let r = 0; r < 4; r++) for (let k = 0; k < 3; k++) px(v.x + 2 + k * 2, v.y + 3 + r * 4, 1, 2, [ROLE.body, ROLE.key, ROLE.live, ROLE.attention][(r + k) % 4]!)
        px(v.x + 9, v.y + 4, 2, 6, ROLE.edge); px(v.x + 9, v.y + 12, 2, 2, f % 2 ? ROLE.live : ROLE.edge)
        px(v.x + 1, v.y + 20, 10, 3, ROLE.edge)
        if (sim.at("vending").length && tick % 40 < 8) px(v.x + 4, v.y + 18 + Math.min(3, (tick % 40) >> 1), 2, 2, ROLE.key)
      })
    },
  }
}
