import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { EMPTY } from "../kit/types"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office } from "./golden"

const at = new Date(2026, 9, 5, 21, 0)

describe("the channel down", () => {
  test("the manager's and the lead's desks stay where they were; their plates say nothing they can't know", () => {
    const room = new WideRoom(560), a = viewOf(office(4), 1)
    for (let i = 0; i < 30; i++) room.step(a)
    // an exec desk registers its sitter over the whole desk, 38 px tall (`execDesk`'s hitH)
    const desks = (hits: { h: number; act: { kind: string } }[]) => hits.filter((h) => h.act.kind === "person" && h.h === 38).length
    const texts = (ink: { t: string; s?: string }[]) => ink.flatMap((i) => (i.t === "text" && i.s ? [i.s] : []))
    const up = room.render(a, focus, measure, at)
    expect(desks(up.hits)).toBe(2)

    const down = { ...EMPTY, note: "channel down (http://127.0.0.1:4040)" }
    room.step(down)
    const fr = room.render(down, focus, measure, at)
    expect(desks(fr.hits)).toBe(2)
    expect(texts(fr.ink)).not.toContain("inbox clear")
    expect(texts(fr.ink)).not.toContain("bench")
  })
})
