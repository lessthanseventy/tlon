import { describe, expect, test } from "bun:test"
import { roll, nextSeed, BORGES } from "../kit/hall"

const VOCAB = { archetypes: ["builder", "reviewer", "planner"], grades: ["junior", "senior", "greybeard"], specialties: ["office", "server"] }
const LEGAL = /^[a-z0-9][a-z0-9_-]*$/

describe("hall roll", () => {
  test("same (seed, locks, taken) → identical candidate", () => {
    expect(roll("hall:7", { taken: [], locks: {}, vocab: VOCAB })).toEqual(roll("hall:7", { taken: [], locks: {}, vocab: VOCAB }))
  })
  test("every Borges name is legal", () => {
    expect(BORGES.length).toBeGreaterThanOrEqual(24)
    for (const n of BORGES) expect(n).toMatch(LEGAL)
  })
  test("the name is legal and not already taken", () => {
    const taken = BORGES.slice(0, BORGES.length - 1)
    const c = roll("hall:3", { taken, locks: {}, vocab: VOCAB })
    expect(c.name).toMatch(LEGAL)
    expect(taken).not.toContain(c.name)
  })
  test("all names taken → a seeded original name, still legal", () => {
    const c = roll("hall:3", { taken: [...BORGES], locks: {}, vocab: VOCAB })
    expect(c.name).toMatch(LEGAL)
    expect(BORGES as readonly string[]).not.toContain(c.name)
  })
  test("a pass keeps locked slots and locked fields from the previous candidate", () => {
    const a = roll("hall:1", { taken: [], locks: {}, vocab: VOCAB })
    const b = roll("hall:2", { taken: [], locks: { slots: ["head", "hand"], fields: ["grade"] }, prev: a, vocab: VOCAB })
    expect(b.look.parts?.head).toEqual(a.look.parts?.head)
    expect(b.look.parts?.hand).toEqual(a.look.parts?.hand)
    expect(b.grade).toBe(a.grade)
    expect(b.seed).toBe("hall:2")
  })
  test("a locked name that has since been taken re-rolls", () => {
    const a = roll("hall:1", { taken: [], locks: {}, vocab: VOCAB })
    const b = roll("hall:2", { taken: [a.name], locks: { fields: ["name"] }, prev: a, vocab: VOCAB })
    expect(b.name).not.toBe(a.name)
    const c = roll("hall:2", { taken: [], locks: { fields: ["name"] }, prev: a, vocab: VOCAB })
    expect(c.name).toBe(a.name)
  })
  test("pitch and soul skeleton are deterministic text, drawn=false", () => {
    const c = roll("hall:9", { taken: [], locks: {}, vocab: VOCAB })
    expect(c.pitch.length).toBeGreaterThan(0)
    expect(c.soul).toContain("## Wants")
    expect(c.soul).not.toContain("## Diary")
    expect(c.drawn).toBe(false)
  })
  test("nextSeed counts hall:<n> up", () => {
    expect(nextSeed("hall:41")).toBe("hall:42")
    expect(nextSeed("junk")).toBe("hall:1")
  })
})
