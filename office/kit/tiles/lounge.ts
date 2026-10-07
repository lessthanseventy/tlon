// The lounge: couches facing the TV, windows, the one plant that's the lounge's, a chat, a pet
// spot, the reading nook (the bookshelf, its armchair).
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { ROLE, tint } from "../palette"
import { at, type Rect, type Tile } from "../tiles"
import type { Spot } from "../sim"
import type { Agents } from "../types"
import { BIG_PLANT } from "../sprites"
import { corner, type Layout, type Zones } from "../../rooms/wide"

export function loungeTile(z: Zones): Tile<Layout> {
  const { L0, Mc } = z
  const { shelf } = corner(z)
  const couch = (x: number, y: number, aisle: number): Spot => ({ x, y, aisle, pose: "couch", face: "up", kind: "couch" })

  return {
    kind: "lounge",
    blocks: (): Rect[] => [{ x: L0 + 34, y: 68, w: 54, h: 10 }],
    spots: () => ({
      couch: [couch(L0 + 44, 82, 94), couch(L0 + 60, 82, 94), couch(L0 + 76, 82, 94), couch(L0 + 30, 150, 150)],
      window: [at(Mc - 32, 54, 116, "up", "window"), at(Mc + 32, 54, 116, "up", "window")],
      plant: [at(L0 + 22, 184, 184, "left", "plant")],
      chat: [at(L0 + 52, 124, 124, "right", "chat", { x: L0 + 66, y: 124 }), at(L0 + 66, 124, 124, "left", "chat", { x: L0 + 52, y: 124 })],
      pet: [at(L0 + 90, 118, 118, "right", "pet"), at(L0 + 40, 106, 106, "right", "pet")],
      read: [{ x: shelf.x + 8, y: 84, aisle: 94, pose: "sit", face: "down", kind: "read" }],
    }),
    draw(sc: Scene, _a: Agents, _l: Layout, _m: Measure) {
      const px = sc.px.bind(sc), blit = sc.blit.bind(sc)
      // the rug, the couch (its back toward you), a lamp, a beanbag
      px(L0 + 34, 48, 54, 14, ROLE.structure); px(L0 + 35, 49, 52, 12, ROLE.borderInactive)
      for (let i = 0; i < 8; i++) px(L0 + 38 + i * 6, 52 + (i % 2) * 4, 2, 2, ROLE.meta)
      sc.item(82.5, () => {
        px(L0 + 34, 76, 56, 8, ROLE.structure); px(L0 + 35, 77, 54, 1, ROLE.borderInactive)
        px(L0 + 32, 70, 4, 14, ROLE.structure); px(L0 + 88, 70, 4, 14, ROLE.structure)
      })
      sc.item(84, () => { px(L0 + 14, 60, 1, 24, ROLE.inactive); px(L0 + 12, 84, 5, 1, ROLE.inactive); blit(["sssss", ".sss."], L0 + 12, 57, { s: ROLE.body }) })
      sc.item(150, () => { px(L0 + 22, 140, 18, 10, ROLE.attention); px(L0 + 24, 138, 14, 3, tint(ROLE.attention, ROLE.ground, 0.7)) })
      sc.item(186, () => blit(BIG_PLANT, L0 + 4, 175, { l: ROLE.live, o: ROLE.structure }))
      sc.item(shelf.y + shelf.h, () => {
        // the bookshelf: three shelves of spines
        px(shelf.x, shelf.y, shelf.w, shelf.h, ROLE.structure)
        for (let r = 0; r < 3; r++) for (let k = 0; k < 9; k++) if ((k * 7 + r * 3) % 10 !== 0) px(shelf.x + 2 + k * 2, shelf.y + 2 + r * 6, 1, 5 - ((k + r) % 2), [ROLE.alarm, ROLE.key, ROLE.body, ROLE.live, ROLE.assistant][(k + r * 2) % 5]!)
      })
      // the armchair in front of it, drawn just behind whoever sits in it
      sc.item(83, () => { px(shelf.x + 1, 72, 14, 12, ROLE.planner); px(shelf.x + 3, 74, 10, 8, tint(ROLE.planner, ROLE.ground, 0.6)); px(shelf.x + 1, 84, 2, 2, ROLE.structure); px(shelf.x + 13, 84, 2, 2, ROLE.structure) })
    },
  }
}
