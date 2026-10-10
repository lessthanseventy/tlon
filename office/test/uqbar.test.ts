import { describe, expect, test } from "bun:test"
import { crewOf, peopleOf, viewOf } from "../kit/crew"
import { readFileSync } from "node:fs"
import { focus, frameHashes, GOLDEN, measure, office, seeded } from "./golden"

const withUqbar = (thinking = false) => {
  const a = office(3)
  return { ...a, roster: [...a.roster, { agent: "uqbar", thread_id: 101, title: "t1", warm: false, thinking, workspace_id: 1 }] }
}

describe("uqbar in the view", () => {
  test("is lifted out of the roster: no desk, no crew row, no person", () => {
    const v = viewOf(withUqbar(), 1)
    expect(v.uqbar).toMatchObject({ agent: "uqbar", thread_id: 101 })
    expect(v.roster.some((r) => r.agent === "uqbar")).toBe(false)
    expect(crewOf(v).some((c) => c.name === "uqbar")).toBe(false)
    expect(peopleOf(v).some((p) => p.agent === "uqbar")).toBe(false)
  })
  test("is seen from any workspace, and absent without a session", () => {
    expect(viewOf(withUqbar(), 2).uqbar).not.toBeNull()
    expect(viewOf(office(3), 1).uqbar).toBeNull()
  })
})

import { FRAMES, goalOf, modeOf, moodOf, RIBBON, spineHome, stepBook, wiggle, type Book } from "../kit/uqbar"
import { ROLE, tint } from "../kit/palette"
import { corner, WideRoom, zones } from "../rooms/wide"

describe("the volume", () => {
  test("every frame is rectangular, 12 wide at most, and uses only known paint", () => {
    for (const [name, rows] of Object.entries(FRAMES)) {
      expect(rows.length, name).toBeLessThanOrEqual(8)
      for (const r of rows) { expect(r.length, name).toBe(rows[0]!.length); expect(r, name).toMatch(/^[.rgpkw]+$/) }
    }
    expect(Object.keys(FRAMES).sort()).toEqual(["closed", "flapDown", "flapUp", "open", "riffle"])
  })
  test("the ribbon is a role per state, all different", () => {
    const c = (["idle", "working", "shipped", "failing"] as const).map((m) => RIBBON[m]())
    expect(new Set(c).size).toBe(4)
    expect(RIBBON.working()).toBe(ROLE.reviewer)
  })
  test("mood: mid-turn is working, otherwise idle", () => {
    expect(moodOf({ agent: "uqbar", thread_id: 1, title: "", warm: false, thinking: true })).toBe("working")
    expect(moodOf({ agent: "uqbar", thread_id: 1, title: "", warm: false })).toBe("idle")
  })
  test("a book flies to its goal at speed, riffling on takeoff, and lands exactly", () => {
    const home = { x: 0, y: 0 }, goal = { x: 30, y: 40 }
    let b: Book = { ...home, flying: false, riffle: 0 }
    expect(modeOf(b, home)).toBe("shelved")
    b = stepBook(b, goal)
    expect(b.flying).toBe(true); expect(b.riffle).toBeGreaterThan(0); expect(modeOf(b, home)).toBe("flying")
    for (let i = 0; i < 100 && b.flying; i++) b = stepBook(b, goal)
    expect(b).toEqual({ x: 30, y: 40, flying: false, riffle: 0 })
    expect(modeOf(b, home)).toBe("perched")
    for (let i = 0; i < 100 && (b.flying || modeOf(b, home) !== "shelved"); i++) b = stepBook(b, home)
    expect(modeOf(b, home)).toBe("shelved")
  })
  test("the goal is the focus card, else the board's edge, else home", () => {
    const home = { x: 1, y: 1 }, edge = { x: 9, y: 0 }, cards = new Map([[101, { x: 5, y: 5 }]])
    const seat = (thread_id: number) => ({ agent: "uqbar", thread_id, title: "", warm: false })
    expect(goalOf(null, cards, edge, home)).toEqual(home)
    expect(goalOf(seat(101), cards, edge, home)).toEqual({ x: 5, y: 5 })
    expect(goalOf(seat(999), cards, edge, home)).toEqual(edge)
  })
  test("the spine wiggles now and then, deterministically from the tick", () => {
    expect(wiggle(0)).toBe(0)
    const on = Array.from({ length: 1800 }, (_, t) => wiggle(t)).filter(Boolean).length
    expect(on).toBeGreaterThan(0); expect(on).toBeLessThan(20)
    expect(wiggle(5)).toBe(wiggle(5 + 1800))
  })
})

const WIDTH = 696, NOW = new Date(2026, 9, 5, 21, 0)
const OX = () => tint(ROLE.alarm, ROLE.ground, 0.6).toUpperCase()
const px = (fr: { rgba: Uint8ClampedArray | Uint8Array; width: number }, x: number, y: number) => {
  const i = (y * fr.width + x) * 4
  return "#" + [0, 1, 2].map((k) => fr.rgba[i + k]!.toString(16).padStart(2, "0")).join("").toUpperCase()
}
const shot = (a: ReturnType<typeof withUqbar>, ticks: number) => seeded(3, () => {
  const room = new WideRoom(WIDTH), v = viewOf(a, 1)
  room.render(v, focus, measure, NOW) // the whiteboard's perches come from a render
  for (let i = 0; i < ticks; i++) room.step(v)
  return room.render(v, focus, measure, NOW)
})
const spot = () => spineHome(corner(zones(WIDTH)).shelf)

describe("uqbar in the wide room", () => {
  test("no session: one extra spine on the shelf, no book anywhere else", () => {
    const fr = shot(office(3) as never, 300), h = spot()
    expect(px(fr, h.x, h.y + 3)).toBe(OX())
    expect(fr.hits.some((x) => x.tip?.startsWith("Uqbar"))).toBe(false)
  })
  test("a live session: the spine is gone and the book perches on its focus card", () => {
    const fr = shot(withUqbar(true), 600), h = spot()
    expect(px(fr, h.x, h.y + 3)).not.toBe(OX())
    const book = fr.hits.find((x) => x.tip?.startsWith("Uqbar"))!
    const card = fr.hits.find((x) => x.tip?.startsWith("#101 "))!
    expect(book).toBeDefined(); expect(card).toBeDefined()
    expect(book.y).toBeLessThan(41)
    expect(book.x).toBeGreaterThanOrEqual(card.x); expect(book.x).toBeLessThanOrEqual(card.x + card.w)
    expect(book.tip).toContain("working")
  })
  test("the session ends: it flies home and the spine is back", () => {
    seeded(3, () => {
      const room = new WideRoom(WIDTH), up = viewOf(withUqbar(), 1), down = viewOf(office(3), 1)
      room.render(up, focus, measure, NOW)
      for (let i = 0; i < 600; i++) room.step(up)
      for (let i = 0; i < 600; i++) room.step(down)
      const fr = room.render(down, focus, measure, NOW)
      expect(px(fr, spot().x, spot().y + 3)).toBe(OX())
    })
  })
})

describe("torn pages", () => {
  type Inner = { planes: { phase: string; at: { x: number; y: number } }[]; actors: Map<string, { x: number; y: number; seat: { agent: string } }>; cards: Map<number, { x: number; y: number }>; fly(tid: number, a: unknown): void }
  /** fly a plane to `tid`, run it out, and return where it was when it finished gliding */
  const flight = (a: ReturnType<typeof office>, tid: number) => seeded(3, () => {
    const room = new WideRoom(WIDTH), v = viewOf(a, 1), r = room as unknown as Inner
    room.render(v, focus, measure, NOW)
    for (let i = 0; i < 300; i++) room.step(v)
    r.fly(tid, v)
    expect(r.planes.length).toBe(1)
    let last = r.planes[0]!.at
    for (let i = 0; i < 400 && r.planes.length; i++) {
      room.step(v)
      const p = r.planes.find((x) => x.phase === "glide")
      if (p) last = p.at
    }
    expect(r.planes.length).toBe(0)
    return { last, r }
  })
  test("a post to a led thread flies to the lead's desk", () => {
    const { last, r } = flight(office(3), 102)
    const lead = r.actors.get("w0")!
    expect(last).toEqual({ x: lead.x, y: lead.y - 10 })
  })
  const unled = (tid: number) => {
    const a = office(3)
    a.threads = a.threads.map((t) => (t.id === tid ? { ...t, lead: null } : t))
    return a
  }
  test("a thread with no lead is delivered to its whiteboard card", () => {
    const { last, r } = flight(unled(101), 101)
    expect(r.cards.get(101)).toBeDefined()
    expect(last).toEqual(r.cards.get(101)!)
  })
  test("no lead and no card: the board's edge", () => {
    const { last, r } = flight(unled(102), 102)
    expect(r.cards.has(102)).toBe(false)
    expect(last).toEqual((r as unknown as { boardEdge: { x: number; y: number } }).boardEdge)
  })
  test("a hand-off flight passes over the old lead's desk first", () => {
    const seen = seeded(3, () => {
      const room = new WideRoom(WIDTH), v = viewOf(office(3), 1), r = room as unknown as Inner & { fly(t: number, a: unknown, p: string): void }
      room.render(v, focus, measure, NOW)
      for (let i = 0; i < 300; i++) room.step(v)
      r.fly(102, v, "w1")
      const old = r.actors.get("w1")!, hit: boolean[] = []
      while (r.planes.length) { room.step(v); hit.push(r.planes.some((p) => p.phase === "glide" && p.at.x === old.x && p.at.y === old.y - 10)) }
      return hit.some(Boolean)
    })
    expect(seen).toBe(true)
  })
  test("Argos catches every 4th plane: he runs under it, it is held, the post still lands", () => {
    seeded(3, () => {
      const room = new WideRoom(WIDTH), v = viewOf(office(3), 1)
      type R = { planes: { legs: { hold?: number }[] }[]; dog: { path: unknown[] }; fly(t: number, a: unknown): void }
      const r = room as unknown as R
      room.render(v, focus, measure, NOW)
      for (let i = 0; i < 300; i++) room.step(v)
      const held: boolean[] = []
      for (let n = 0; n < 4; n++) {
        r.dog.path = []
        r.fly(102, v)
        held.push(r.planes.at(-1)!.legs.some((l) => l.hold))
        if (n === 3) expect(r.dog.path.length).toBeGreaterThan(0)
      }
      expect(held).toEqual([false, false, false, true])
      for (let i = 0; i < 1500 && r.planes.length; i++) room.step(v)
      expect(r.planes.length).toBe(0)
    })
  })
  test("no plane in flight: the golden frames do not move", () => {
    expect(frameHashes()).toEqual(JSON.parse(readFileSync(GOLDEN, "utf8")))
  })
})
