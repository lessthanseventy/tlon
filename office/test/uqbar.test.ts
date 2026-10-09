import { describe, expect, test } from "bun:test"
import { crewOf, peopleOf, viewOf } from "../kit/crew"
import { office } from "./golden"

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

import { FRAMES, goalOf, modeOf, moodOf, RIBBON, stepBook, wiggle, type Book } from "../kit/uqbar"
import { ROLE } from "../kit/palette"

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
