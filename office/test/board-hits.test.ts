import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom, WIDE_H } from "../rooms/wide"
import { geometry, hitAt, measureFor } from "../tui/paint"
import { focus, office, seeded } from "./golden"

// a whiteboard line is a target ~6 art px tall; a terminal row samples the frame once per cell, so a
// line must stay reachable from some cell at every cell size, not just the ones whose centre lands on it
describe("every whiteboard line can be hovered and clicked", () => {
  const a = office(4)
  a.threads = a.threads.map((t, i) => (i < 4 ? { ...t, stage: "review" } : t))
  const v = viewOf(a, 1)
  for (const h of [14, 16, 17, 18, 19, 20, 21, 22, 24, 26]) {
    test(`a ${h}px-tall cell`, () => seeded(3, () => {
      const g = geometry(696, WIDE_H, 220, 70, 8, { w: Math.round(h / 2), h }, true)
      const r = new WideRoom(696), fr = r.render(v, focus, measureFor(g), new Date(2026, 9, 5, 15, 0))
      const lines = fr.hits.filter((x) => x.act?.kind === "thread" && x.y < 40)
      expect(lines.length).toBeGreaterThanOrEqual(1)
      for (const line of lines) {
        let reached = false
        for (let row = g.row + 1; row <= g.row + g.rows && !reached; row++)
          for (let col = g.col + 1; col <= g.col + g.cols && !reached; col++) reached = hitAt(fr, g, col, row) === line
        expect({ tip: line.tip?.split("\n")[0], reached }).toEqual({ tip: line.tip?.split("\n")[0], reached: true })
      }
    }))
  }
})
