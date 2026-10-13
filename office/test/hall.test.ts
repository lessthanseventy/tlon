import { describe, expect, test } from "bun:test"
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { roll, nextSeed, BORGES, loadHall, saveHall, hallSignature, applyOverrides, pushPile, dropPile, PILE_MAX, candidateOf, pass, maybe, bringBack, takenNames, toggleLock, emptyHall } from "../kit/hall"

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

describe("hall.json", () => {
  const tmp = () => join(mkdtempSync(join(tmpdir(), "hall-")), "hall.json")
  test("round trip keeps seed, locks, overrides and the pile", () => {
    const p = tmp()
    const s = { seed: "hall:5", locks: { slots: ["eyes" as const] }, overrides: { name: "borges" }, pile: [{ seed: "hall:2", overrides: {} }] }
    saveHall(p, s)
    expect(loadHall(p)).toEqual(s)
  })
  test("a missing or corrupt file is the empty hall, not a crash", () => {
    expect(loadHall("/nonexistent/hall.json").pile).toEqual([])
    const p = tmp()
    writeFileSync(p, "{not json")
    expect(loadHall(p).pile).toEqual([])
    expect(loadHall(p).seed).toBe("hall:1")
  })
  test("saveHall creates the directory", () => {
    const p = join(mkdtempSync(join(tmpdir(), "hall-")), "a", "b", "hall.json")
    saveHall(p, { seed: "hall:1", locks: {}, overrides: {}, pile: [] })
    expect(loadHall(p).seed).toBe("hall:1")
  })
  test("hallSignature is empty when absent and changes with the file", () => {
    const p = tmp()
    expect(hallSignature(p)).toBe("")
    saveHall(p, { seed: "hall:1", locks: {}, overrides: {}, pile: [] })
    const a = hallSignature(p)
    expect(a).not.toBe("")
    saveHall(p, { seed: "hall:1", locks: {}, overrides: { name: "x" }, pile: [] })
    writeFileSync(p, JSON.stringify({ seed: "hall:9", locks: {}, overrides: {}, pile: [] }) + "\n", { flag: "w" })
    expect(hallSignature(p)).not.toBe(a)
  })
  test("a pile entry re-renders identically from seed + overrides", () => {
    const c = roll("hall:2", { taken: [], locks: {}, vocab: VOCAB })
    expect(applyOverrides(roll("hall:2", { taken: [], locks: {}, vocab: VOCAB }), {})).toEqual(c)
  })
  test("overrides replace fields but never the seed", () => {
    const c = applyOverrides(roll("hall:2", { taken: [], locks: {}, vocab: VOCAB }), { name: "zed", grade: "senior", seed: "evil" } as never)
    expect(c.name).toBe("zed")
    expect(c.grade).toBe("senior")
    expect(c.seed).toBe("hall:2")
  })
  test("the pile pushes, drops by index, and caps", () => {
    let pile = pushPile([], { seed: "hall:1", overrides: {} })
    pile = pushPile(pile, { seed: "hall:2", overrides: {} })
    expect(pile.map(e => e.seed)).toEqual(["hall:1", "hall:2"])
    expect(dropPile(pile, 0).map(e => e.seed)).toEqual(["hall:2"])
    expect(dropPile(pile, 9)).toEqual(pile)
    let big = pile
    for (let i = 0; i < PILE_MAX + 5; i++) big = pushPile(big, { seed: `hall:${i + 10}`, overrides: {} })
    expect(big.length).toBe(PILE_MAX)
    expect(big.at(-1)!.seed).toBe(`hall:${PILE_MAX + 5 + 9}`)
  })
  test("a part override replaces a slot, null clears it; the seed's other slots stay", () => {
    const c = roll("hall:2", { taken: [], locks: {}, vocab: VOCAB })
    const spec = { id: "x-part", dials: {} }
    const o = applyOverrides(c, { parts: { head: spec as never, hand: null } })
    expect(o.look.parts?.head).toEqual(spec as never)
    expect(o.look.parts?.hand).toBeUndefined()
    expect(o.look.parts?.eyes).toEqual(c.look.parts?.eyes)
    expect(c.look.parts?.head).not.toEqual(spec as never)
  })
  test("a hand-edited hall.json with junk locks loads as legal locks only", () => {
    const p = tmp()
    writeFileSync(p, JSON.stringify({ seed: "hall:3", locks: { slots: "head", fields: ["grade", "bogus", 3] }, overrides: {}, pile: [] }))
    expect(loadHall(p).locks).toEqual({ fields: ["grade"] })
    writeFileSync(p, JSON.stringify({ seed: "hall:3", locks: { slots: ["eyes", "nope"], fields: 3 }, overrides: {}, pile: [] }))
    expect(loadHall(p).locks).toEqual({ slots: ["eyes"] })
  })
  test("pushing a seed already in the pile replaces it, not duplicates it", () => {
    let pile = pushPile([], { seed: "hall:1", overrides: {} })
    pile = pushPile(pile, { seed: "hall:2", overrides: {} })
    pile = pushPile(pile, { seed: "hall:1", overrides: { name: "edited" } })
    expect(pile.map(e => e.seed)).toEqual(["hall:2", "hall:1"])
    expect(pile.at(-1)!.overrides.name).toBe("edited")
  })
})

describe("the hall's turn-by-turn state", () => {
  const o = { taken: [] as string[], vocab: VOCAB }
  const hall = (over = {}) => ({ ...emptyHall(), ...over })
  test("candidateOf is roll + overrides, so a stored hall re-renders identically", () => {
    const h = hall({ seed: "hall:4", overrides: { grade: "senior" } })
    expect(candidateOf(h, o)).toEqual(applyOverrides(roll("hall:4", { ...o, locks: {} }), { grade: "senior" }))
  })
  test("a pass moves to the next seed and bakes locked values into the overrides", () => {
    const h = hall({ seed: "hall:1", locks: { slots: ["head" as const], fields: ["grade" as const] } })
    const a = candidateOf(h, o), next = pass(h, o)
    expect(next.seed).toBe("hall:2")
    const b = candidateOf(next, o)
    expect(b.grade).toBe(a.grade)
    expect(b.look.parts?.head).toEqual(a.look.parts?.head)
    expect(candidateOf(JSON.parse(JSON.stringify(next)), o)).toEqual(b)
    expect(next.locks).toEqual(h.locks)
  })
  test("a pass with no locks drops the previous overrides", () => {
    expect(pass(hall({ overrides: { name: "zed" } }), o).overrides).toEqual({})
  })
  test("maybe puts the current card on the pile, then passes", () => {
    const h = hall({ seed: "hall:1", overrides: { grade: "senior" } })
    const m = maybe(h, o)
    expect(m.pile).toEqual([{ seed: "hall:1", overrides: { grade: "senior" } }])
    expect(m.seed).toBe("hall:2")
  })
  test("bringBack makes a pile entry the current card and takes it off the pile", () => {
    const h = hall({ seed: "hall:9", pile: [{ seed: "hall:1", overrides: { name: "zed" } }, { seed: "hall:2", overrides: {} }] })
    const b = bringBack(h, 0)
    expect(b.seed).toBe("hall:1")
    expect(b.overrides).toEqual({ name: "zed" })
    expect(b.pile.map(e => e.seed)).toEqual(["hall:2"])
    expect(bringBack(h, 7)).toEqual(h)
  })
  test("takenNames is the bench and the pile's names", () => {
    const h = hall({ pile: [{ seed: "hall:1", overrides: { name: "zed" } }, { seed: "hall:2", overrides: {} }] })
    const names = takenNames(h, ["funes"], VOCAB)
    expect(names).toContain("funes")
    expect(names).toContain("zed")
    expect(names).toContain(roll("hall:2", { taken: ["funes"], locks: {}, vocab: VOCAB }).name)
  })
  test("toggleLock flips a slot or field and drops empty lists", () => {
    let l = toggleLock({}, "slots", "head")
    expect(l).toEqual({ slots: ["head"] })
    l = toggleLock(l, "fields", "grade")
    expect(l).toEqual({ slots: ["head"], fields: ["grade"] })
    expect(toggleLock(toggleLock(l, "slots", "head"), "fields", "grade")).toEqual({})
  })
})
