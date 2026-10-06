import { describe, expect, test } from "bun:test"
import { boardColumns, crewOf, viewOf } from "../kit/crew"
import { EMPTY, type Agents } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"

const measure = (s: string) => s.length * 2
const focus = { picked: null, armed: null, person: null }

/** a workspace with a manager, a lead and `grunts` builders, all at work */
function office(grunts: number): Agents {
  const names = ["tertius", "hronir", ...Array.from({ length: grunts }, (_, i) => `w${i}`)]
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }, { id: 2, name: "Other" }],
    archetypes: [{ name: "surveyor", meta: true, read_only: true, model: "" }, { name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: i === 0 ? "surveyor" : "builder", lead: i === 1, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `t${i}`, stage: i === 1 ? "build" : null, awaiting: null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: true, thinking: true, workspace_id: 1 })),
    tickets: [{ id: 7, workspace_id: 1, project_id: null, title: "a ticket", priority: "high" }, { id: 8, workspace_id: 2, project_id: null, title: "elsewhere", priority: "normal" }],
  }
}
function settle(room: RailRoom, a: Agents) { for (let i = 0; i < 400; i++) room.step(a) }

describe("the rail room", () => {
  test("renders a full frame of the fixed size", () => {
    const room = new RailRoom(), a = viewOf(office(3), 1)
    settle(room, a)
    const fr = room.render(a, focus, measure)
    expect([fr.width, fr.height]).toEqual([W, H])
    expect(fr.rgba.length).toBe(W * H * 4)
    // every pixel painted: the floors cover the room
    for (let i = 3; i < fr.rgba.length; i += 4) expect(fr.rgba[i]).toBe(255)
  })

  test("a full office of ten seats everyone, each at their own place", () => {
    const room = new RailRoom(), a = viewOf(office(8), 1)
    settle(room, a)
    const fr = room.render(a, focus, measure)
    const seated = fr.hits.filter((h) => h.act.kind === "person" && h.tip.includes("at the desk"))
    expect(seated.length).toBe(10)
    const spots = new Set(seated.map((h) => `${h.x},${h.y}`))
    expect(spots.size).toBe(10)
    for (const h of fr.hits) {
      expect(h.x).toBeGreaterThanOrEqual(-1)
      expect(h.x + h.w).toBeLessThanOrEqual(W + 1)
      expect(h.y + h.h).toBeLessThanOrEqual(H + 1)
    }
  })

  test("text and balloons come out as ink, not pixels", () => {
    const room = new RailRoom(), a = viewOf(office(1), 1)
    settle(room, a)
    room.say("hronir", "done — merged the thing")
    const ink = room.render(a, focus, measure).ink
    expect(ink.some((i) => i.t === "text" && i.s === "CREW")).toBe(true)
    expect(ink.some((i) => i.t === "text" && i.s.startsWith("hronir"))).toBe(true)
    expect(ink.find((i) => i.t === "balloon")).toMatchObject({ lines: ["done - merged the thing"] })
  })
})

describe("the data views", () => {
  test("a workspace's view keeps only its own", () => {
    const v = viewOf(office(2), 2)
    expect([v.bench.length, v.threads.length, v.tickets.map((t) => t.id)]).toEqual([0, 0, [8]])
  })

  test("the crew and the board agree with the snapshot", () => {
    const v = viewOf(office(1), 1)
    expect(crewOf(v).map((c) => [c.name, c.manager, c.lead, c.status])).toEqual([
      ["tertius", true, false, "working"], ["hronir", false, true, "working"], ["w0", false, false, "working"],
    ])
    const cols = boardColumns(v)
    expect(cols[0]!.items.map((i) => i.title)).toEqual(["a ticket"])
    expect(cols[4]!.items.map((i) => i.who)).toEqual(["hronir"])
  })
})
