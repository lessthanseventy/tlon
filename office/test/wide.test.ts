import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import type { Spot } from "../kit/sim"
import { EMPTY, type Agents } from "../kit/types"
import { WIDE_H, WideRoom, widePlan } from "../rooms/wide"

const measure = (s: string) => s.length * 2
const focus = { picked: null, armed: null, person: null }

function office(grunts: number): Agents {
  const names = ["tertius", "hronir", ...Array.from({ length: grunts }, (_, i) => `w${i}`)]
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "surveyor", meta: true, read_only: true, model: "" }, { name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: i === 0 ? "surveyor" : "builder", lead: i === 1, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `thread ${i}`, stage: i === 1 ? "build" : null, awaiting: null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: true, workspace_id: 1 })),
    notes: [{ id: 1, author: "hronir", body: "a note", workspace_id: 1, at: new Date(0).toISOString() }],
  }
}

describe("the wide room", () => {
  for (const w of [470, 485, 640]) {
    test(`renders a full frame ${w} wide`, () => {
      const room = new WideRoom(w), a = viewOf(office(3), 1)
      for (let i = 0; i < 300; i++) room.step(a)
      const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
      expect([fr.width, fr.height]).toEqual([w, WIDE_H])
      for (let i = 3; i < fr.rgba.length; i += 4) expect(fr.rgba[i]).toBe(255)
      for (const h of fr.hits) { expect(h.x).toBeGreaterThanOrEqual(-1); expect(h.x + h.w).toBeLessThanOrEqual(w + 1) }
    })
  }

  test("a full office of ten seats everyone, each at their own place", () => {
    const room = new WideRoom(485), a = viewOf(office(8), 1)
    for (let i = 0; i < 400; i++) room.step(a)
    const seated = room.render(a, focus, measure).hits.filter((h) => h.act.kind === "person" && h.tip.includes("at the desk"))
    expect(seated.length).toBe(10)
    expect(new Set(seated.map((h) => `${h.x},${h.y}`)).size).toBe(10)
  })

  test("no walk crosses the furniture", () => {
    for (const w of [470, 560, 700]) {
      const plan = widePlan(w), l = plan.layout(viewOf(office(8), 1))
      const homes = l.people.map((p) => plan.home(l, p.agent)).filter((s): s is Spot => !!s)
      const spots = [...homes, ...plan.queue, ...plan.lounge, plan.exit, plan.pen, plan.roam(l)]
      const blocks = plan.blocks(l)
      const inside = (x: number, y: number) => blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
      for (const from of spots) for (const to of spots) {
        const start = from.kind === "desk" || from.kind === "queue" ? from.aisle : from.y
        const path = plan.route(from.x, start, to)
        // the first and last legs sit down and stand up; everything between is walking
        let x = path[0]!.x, y = path[0]!.y
        for (const p of path.slice(1, -1)) {
          while (x !== p.x || y !== p.y) {
            if (x !== p.x) x += Math.sign(p.x - x); else y += Math.sign(p.y - y)
            const hit = inside(x, y)
            if (hit) throw new Error(`${from.kind}@${from.x},${from.y} → ${to.kind}@${to.x},${to.y} (w ${w}) walks through ${JSON.stringify(hit)} at ${x},${y}`)
          }
        }
      }
    }
  })
})
