// The mailbox on the street tile: the operator's needs queue (`Server.Office.Needs`) as letters.
// Blocking needs raise the flag, so the state is never colour alone.
import type { Scene } from "./draw"
import { ROLE } from "./palette"

/** letters the box shows before it is just "full"; `total` still counts every need */
export const MAX_LETTERS = 5

export type Mailbox = { letters: number; blocking: number; flagUp: boolean; total: number }

export function mailbox(needs: { level: "blocking" | "decide" }[]): Mailbox {
  const blocking = needs.filter((n) => n.level === "blocking").length
  return { letters: Math.min(needs.length, MAX_LETTERS), blocking, flagUp: blocking > 0, total: needs.length }
}

/** the box standing with its foot at (x, y): a post, the box, the flag, the letters peeking out */
export function drawMailbox(sc: Scene, x: number, y: number, mb: Mailbox) {
  const px = sc.px.bind(sc)
  sc.item(y, () => {
    px(x + 5, y - 10, 2, 10, ROLE.inactive)
    px(x, y - 18, 12, 8, ROLE.key); px(x, y - 18, 12, 1, ROLE.borderInactive)
    for (let i = 0; i < mb.letters; i++) px(x + 1 + i * 2, y - 20, 2, 2, ROLE.prose)
    if (mb.flagUp) { px(x + 12, y - 24, 1, 8, ROLE.inactive); px(x + 13, y - 24, 4, 3, ROLE.attention) }
    else px(x + 12, y - 15, 3, 1, ROLE.inactive)
  })
}
