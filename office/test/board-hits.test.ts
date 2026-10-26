import { describe, expect, test } from "bun:test"
import type { Hit } from "../kit/types"
import { RailRoom } from "../rooms/rail"
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

// the TICKETS sticky for loose tickets is a column hit, not a ticket: its tip names no ticket id
test("the TICKETS column's loose sticky tip names no id", () => seeded(3, () => {
  const a = { ...office(4), tickets: [{ id: 7, workspace_id: 1, project_id: null, title: "loose", priority: "normal", kind: "ticket" as const, epic_id: null, status: "todo" }] }
  const g = geometry(696, WIDE_H, 220, 70, 8, { w: 8, h: 16 }, true)
  const fr = new WideRoom(696).render(viewOf(a, 1), focus, measureFor(g), new Date(2026, 9, 5, 15, 0))
  const loose = fr.hits.find((x) => x.act?.kind === "column" && x.tip?.includes("loose"))
  expect(loose?.tip?.split("\n")[0]).toBe("1 loose")
}))

// a column's blank area (below its last line) opens the column, in both rooms; the background hit must not
// swallow a card: hitAt is first-match, so it goes after the column's card hits
describe("a column's empty space opens the column", () => {
  const a = office(4)
  a.threads = a.threads.map((t, i) => (i < 4 ? { ...t, stage: "review" } : t))
  const v = viewOf(a, 1)
  const first = (fr: { hits: Hit[] }, x: number, y: number) => fr.hits.find((h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)

  test("wide: below the last line is the column; every line is still its thread", () => seeded(3, () => {
    const fr = new WideRoom(696).render(v, focus, measureFor(geometry(696, WIDE_H, 220, 70, 8, { w: 8, h: 16 }, true)), new Date(2026, 9, 5, 15, 0))
    const lines = fr.hits.filter((x) => x.act?.kind === "thread" && x.y < 40)
    expect(lines.length).toBeGreaterThanOrEqual(1)
    for (const l of lines) expect(first(fr, l.x + l.w / 2, l.y + l.h / 2)).toBe(l)
    const review = lines[0]!, col = fr.hits.find((h) => h.act?.kind === "column" && h.y === 3 && review.x >= h.x && review.x < h.x + h.w)!
    const below = Math.max(...lines.filter((l) => l.x >= col.x && l.x < col.x + col.w).map((l) => l.y + l.h))
    expect(first(fr, col.x + col.w / 2, below + 4)?.act).toEqual(col.act)
    expect(first(fr, col.x + col.w / 2, 37)?.act).toEqual(col.act)
  }))

  test("rail: the blank area under the stickies is the column; every sticky is still its thread", () => {
    const fr = new RailRoom().render(v, focus, (s: string) => s.length * 2)
    const stickies = fr.hits.filter((h) => h.act?.kind === "thread")
    expect(stickies.length).toBeGreaterThanOrEqual(1)
    for (const s of stickies) expect(first(fr, s.x + s.w / 2, s.y + s.h / 2)).toBe(s)
    const col = fr.hits.find((h) => h.act?.kind === "column" && h.y === 3 && stickies[0]!.x >= h.x && stickies[0]!.x < h.x + h.w)!
    expect(first(fr, col.x + col.w / 2, 22)?.act).toEqual(col.act)
  })
})
