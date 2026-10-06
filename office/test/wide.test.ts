import { describe, expect, test } from "bun:test"
import { crewOf, viewOf } from "../kit/crew"
import type { Spot } from "../kit/sim"
import { EMPTY, type Agents } from "../kit/types"
import { WIDE_H, WideRoom, widePlan } from "../rooms/wide"

const measure = (s: string) => s.length * 2

/** run `f` with Math.random seeded (mulberry32), so a test of the room's chance is the same every run */
function seeded<T>(seed: number, f: () => T): T {
  const real = Math.random
  let a = seed >>> 0
  Math.random = () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
  try { return f() } finally { Math.random = real }
}
const focus = { picked: null, armed: null, person: null }

function office(grunts: number): Agents {
  const names = ["tertius", "hronir", ...Array.from({ length: grunts }, (_, i) => `w${i}`)]
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "surveyor", meta: true, read_only: true, model: "" }, { name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: i === 0 ? "surveyor" : "builder", lead: i === 1, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `thread ${i}`, stage: i === 1 ? "build" : null, awaiting: null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: true, thinking: true, workspace_id: 1 })),
    notes: [{ id: 1, author: "hronir", body: "a note", workspace_id: 1, at: new Date(0).toISOString() }],
  }
}

describe("the wide room", () => {
  for (const w of [540, 560, 640]) {
    test(`renders a full frame ${w} wide`, () => {
      const room = new WideRoom(w), a = viewOf(office(3), 1)
      for (let i = 0; i < 300; i++) room.step(a)
      const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
      expect([fr.width, fr.height]).toEqual([w, WIDE_H])
      for (let i = 3; i < fr.rgba.length; i += 4) expect(fr.rgba[i]).toBe(255)
      for (const h of fr.hits) { expect(h.x).toBeGreaterThanOrEqual(-1); expect(h.x + h.w).toBeLessThanOrEqual(w + 1) }
    })
  }

  test("the in-tray, the beacon and the rack say what they hold, and open their cards", () => {
    const tips = (a: Agents, tray: number) => new Map(new WideRoom(560).render(a, { ...focus, tray }, measure).hits.map((h) => [h.act.kind, h.tip]))
    const quiet = tips(viewOf({ ...office(1), triage: { "1": 0 }, health: { state: "ok", problems: [] } }, 1), 0)
    expect([quiet.get("tray"), quiet.get("beacon"), quiet.get("rack")]).toEqual(["the in-tray: what just happened", "the beacon: nothing is stuck", "the server rack: all green"])
    const busy = tips(viewOf({ ...office(1), triage: { "1": 3, "2": 9 }, health: { state: "warn", problems: ["disk 95% full"] } }, 1), 4)
    expect(busy.get("tray")).toContain("4 new")
    // the beacon counts this workspace's stuck things, never another's
    expect(busy.get("beacon")).toContain("3 stuck")
    expect(busy.get("rack")).toContain("disk 95% full")
  })

  test("mid-turn works at a desk; warm but unbusy waits on call at a laptop; cold goes to the lounge", () => seeded(3, () => {
    const a0 = office(2)
    const state = (i: number) => (i === 1 ? { warm: true, thinking: true } : i === 2 ? { warm: true, thinking: false } : { warm: false, thinking: false })
    const a = viewOf({ ...a0, roster: a0.roster.map((r, i) => ({ ...r, ...state(i) })) }, 1)
    const room = new WideRoom(560)
    for (let i = 0; i < 600; i++) room.step(a)
    const at = (name: string) => (room as unknown as { actors: Map<string, { spot: { kind: string } }> }).actors.get(name)!.spot.kind
    expect([at("hronir"), at("w0")]).toEqual(["desk", "laptop"])
    expect(["couch", "cooler", "coffee", "roam"]).toContain(at("w1"))
    expect(crewOf(a).map((c) => [c.name, c.status])).toEqual([["tertius", "idle"], ["hronir", "working"], ["w0", "idle"], ["w1", "idle"]])
  }))

  test("the pets do what you tell them: Nina naps, zooms, comes to your desk; Argos goes to bed", () => seeded(5, () => {
    const room = new WideRoom(560), a = viewOf(office(1), 1)
    const pets = room as unknown as { cat: { x: number; y: number; mode: string; path: unknown[] }; dog: { x: number; y: number; mode: string; path: unknown[] } }
    const settle = (done: () => boolean) => { for (let i = 0; i < 3_000 && !done(); i++) room.step(a) }

    room.catDo("come")
    settle(() => !pets.cat.path.length)
    expect([pets.cat.x, pets.cat.y]).toEqual([37, 75])
    expect(room.catDo("zoomies")).toBe(true)
    expect(pets.cat.mode).toBe("zoom")

    room.dogDo("bed")
    settle(() => !pets.dog.path.length)
    expect(pets.dog.mode).toBe("sleep")
  }))

  test("the wall calendar counts the days still to come with something scheduled", () => {
    const tip = (calendar: Record<string, number[]>) => new WideRoom(560).render(viewOf({ ...office(1), calendar }, 1), focus, measure, new Date(2026, 9, 10, 12, 0)).hits.find((h) => h.act.kind === "calendar")!.tip
    expect(tip({ "1": [2, 9, 16, 23, 30], "2": [11, 12] })).toContain("something scheduled on 3 day(s) still to come")
    expect(tip({})).not.toContain("scheduled")
  })

  test("a full office of ten seats everyone, each at their own place", () => {
    const room = new WideRoom(560), a = viewOf(office(8), 1)
    for (let i = 0; i < 400; i++) room.step(a)
    const seated = room.render(a, focus, measure).hits.filter((h) => h.act.kind === "person" && h.tip.includes("at the desk"))
    expect(seated.length).toBe(10)
    expect(new Set(seated.map((h) => `${h.x},${h.y}`)).size).toBe(10)
  })

  test("Argos keeps off the furniture, and gets around", () => seeded(13, () => {
    for (const w of [540, 696, 900]) {
      const room = new WideRoom(w), a = viewOf(office(6), 1), plan = widePlan(w), blocks = plan.blocks(plan.layout(a))
      const seen = new Set<string>()
      for (let i = 0; i < 3000; i++) {
        room.step(a)
        const d = (room as unknown as { dog: { x: number; y: number } }).dog
        const hit = blocks.find((b) => d.x > b.x && d.x < b.x + b.w - 1 && d.y > b.y && d.y < b.y + b.h - 1)
        if (hit) throw new Error(`Argos at ${d.x},${d.y} (w ${w}, tick ${i}) is inside ${JSON.stringify(hit)}`)
        seen.add(`${Math.round(d.x / 40)},${Math.round(d.y / 40)}`)
      }
      expect(seen.size).toBeGreaterThan(3)
    }
  }))

  test("Nina and Argos get up to things, and Argos still keeps off the furniture doing it", () => seeded(7, () => {
    const room = new WideRoom(696), a = viewOf(office(6), 1), plan = widePlan(696), blocks = plan.blocks(plan.layout(a))
    const kinds = new Set<string>()
    for (let i = 0; i < 400_000 && kinds.size < 2; i++) {
      room.step(a)
      const r = room as unknown as { dog: { x: number; y: number }; antic: { kind: string } | null }
      if (r.antic) kinds.add(r.antic.kind)
      const hit = blocks.find((b) => r.dog.x > b.x && r.dog.x < b.x + b.w - 1 && r.dog.y > b.y && r.dog.y < b.y + b.h - 1)
      if (hit) throw new Error(`Argos at ${r.dog.x},${r.dog.y} (tick ${i}, ${r.antic?.kind ?? "no antic"}) is inside ${JSON.stringify(hit)}`)
    }
    expect(kinds.size).toBeGreaterThanOrEqual(2)
  }))

  // up to 400k ticks of the room: seconds of CPU, more when the gate runs every suite at once
  test("Nina gets the zoomies: tears between the room's leaps, then lands on its floor and sits", () => seeded(11, () => {
    const room = new WideRoom(696), a = viewOf(office(6), 1)
    const c = (room as unknown as { cat: { x: number; y: number; mode: string; leaps: { x: number; y: number }[] } }).cat
    const visited = new Set<string>()
    let runs = 0, was = c.mode
    for (let i = 0; i < 400_000 && runs < 3; i++) {
      room.step(a)
      if (c.mode === "zoom" && c.leaps.some((q) => q.x === c.x && q.y === c.y)) visited.add(`${c.x},${c.y}`)
      if (was === "zoom" && c.mode !== "zoom") {
        runs++
        expect({ mode: c.mode, at: [c.x, c.y] }).toEqual({ mode: "sit", at: [c.leaps[0]!.x, c.leaps[0]!.y] })
      }
      was = c.mode
    }
    expect(runs).toBe(3)
    expect(visited.size).toBeGreaterThanOrEqual(3)
  }), 30_000)

  test("no walk crosses the furniture", () => {
    for (const w of [540, 560, 700]) {
      const plan = widePlan(w), l = plan.layout(viewOf(office(8), 1))
      const homes = l.people.map((p) => plan.home(l, p.agent)).filter((s): s is Spot => !!s)
      const spots = [...homes, ...plan.queue, ...plan.lounge, ...(plan.oncall ?? []), plan.exit, plan.pen, plan.roam(l)]
      const blocks = plan.blocks(l)
      const inside = (x: number, y: number) => blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
      for (const from of spots) for (const to of spots) {
        const start = from.aisle
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
