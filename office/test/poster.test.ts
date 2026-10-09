import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { posterOf } from "../kit/poster"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office } from "./golden"

describe("the poster of the day", () => {
  test("its line is fixed for a day and changes the next", () => {
    expect(posterOf(new Date(2026, 9, 10, 8))).toBe(posterOf(new Date(2026, 9, 10, 22)))
    expect(posterOf(new Date(2026, 9, 10))).not.toBe(posterOf(new Date(2026, 9, 11)))
  })

  const now = new Date(2026, 9, 10, 12, 0)
  const hits = (w: number) => new WideRoom(w).render(viewOf(office(3), 1), focus, measure, now).hits.filter((h) => h.act.kind === "poster")

  test("a wide room hangs one whose tip is today's line", () => {
    const [hit, ...rest] = hits(900)
    expect(rest).toEqual([])
    expect(hit!.tip).toContain(posterOf(now))
  })
  test("a room too narrow for it keeps the wall as it was", () => {
    expect(hits(540)).toEqual([])
  })
})
