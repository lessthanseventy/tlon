// The meeting room: a round table behind glass, two laptops a side for whoever's on call.
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { ROLE } from "../palette"
import { at, type Rect, type Tile } from "../tiles"
import type { Agents } from "../types"
import { BAND, MEET_BOTTOM, type Layout, type Zones } from "../../rooms/wide"

export function meetingTile(z: Zones): Tile<Layout> {
  const { M0, MW, Mc } = z

  return {
    kind: "meeting",
    blocks: (): Rect[] => [
      { x: M0 - 1, y: BAND, w: 2, h: MEET_BOTTOM - BAND }, { x: M0 + MW - 1, y: BAND, w: 2, h: MEET_BOTTOM - BAND },
      { x: M0, y: MEET_BOTTOM - 1, w: MW / 2 - 9, h: 2 }, { x: Mc + 9, y: MEET_BOTTOM - 1, w: MW / 2 - 9, h: 2 },
      { x: Mc - 14, y: 76, w: 28, h: 20 },
    ],
    spots: () => ({
      laptop: [Mc - 22, Mc + 22].flatMap((x) => [81, 95].map((y) => at(x, y, 116, x < Mc ? "right" : "left", "laptop"))),
    }),
    draw(sc: Scene, _a: Agents, _l: Layout, _m: Measure) {
      const px = sc.px.bind(sc), text = sc.text.bind(sc)
      sc.item(BAND, () => {
        for (const x of [M0, M0 + MW - 1]) px(x, BAND, 1, MEET_BOTTOM - BAND, ROLE.key)
        px(M0, MEET_BOTTOM - 1, MW / 2 - 9, 1, ROLE.key); px(Mc + 9, MEET_BOTTOM - 1, MW / 2 - 9, 1, ROLE.key)
      })
      sc.item(96, () => {
        for (let dy = -10; dy <= 10; dy++) { const half = Math.round(Math.sqrt(100 - dy * dy) * 1.4); px(Mc - half, 86 + dy, half * 2, 1, dy < -8 ? ROLE.body : ROLE.borderInactive) }
        px(Mc - 3, 82, 6, 3, ROLE.prose); px(Mc + 6, 88, 3, 2, ROLE.attention) // papers, a mug
      })
      text("MEETING", Mc, BAND + 9, ROLE.key, 11)
    },
  }
}
