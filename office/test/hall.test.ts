import { afterEach, describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { roll, nextSeed, BORGES, loadHall, saveHall, hallSignature, applyOverrides, pushPile, dropPile, PILE_MAX, candidateOf, pass, maybe, bringBack, takenNames, toggleLock, emptyHall, seatedNames, editField, setLook } from "../kit/hall"

const VOCAB = { archetypes: ["builder", "reviewer", "planner"], grades: ["junior", "senior", "greybeard"], specialties: ["office", "server"] }
const LEGAL = /^[a-z0-9][a-z0-9_-]*$/

describe("hall roll", () => {
  test("same (seed, locks, taken) → identical candidate", () => {
    expect(roll("hall:7", { taken: [], vocab: VOCAB })).toEqual(roll("hall:7", { taken: [], vocab: VOCAB }))
  })
  test("never offers uqbar, the operator's delegate: a seat by that name would take its identity", () => {
    expect(BORGES as readonly string[]).not.toContain("uqbar")
    // the machine's own names are systems and citizens, never a new coworker's
    for (const sys of ["funes", "menard", "aleph", "orbis", "tlon", "borges"]) expect(BORGES as readonly string[]).not.toContain(sys)
    expect(new Set(BORGES).size).toBe(BORGES.length)
    for (let i = 0; i < 300; i++) expect(roll(`hall:${i}`, { taken: [], vocab: VOCAB }).name).not.toBe("uqbar")
  })
  test("every Borges name is legal", () => {
    expect(BORGES.length).toBeGreaterThanOrEqual(24)
    for (const n of BORGES) expect(n).toMatch(LEGAL)
  })
  test("the name is legal and not already taken", () => {
    const taken = BORGES.slice(0, BORGES.length - 1)
    const c = roll("hall:3", { taken, vocab: VOCAB })
    expect(c.name).toMatch(LEGAL)
    expect(taken).not.toContain(c.name)
  })
  test("no name is junk: the list has no hyphenated fragments, and a generated name is a word", () => {
    for (const n of BORGES) expect(n, n).toMatch(/^[a-z]{3,}$/)
    const names = new Set<string>()
    for (let i = 0; i < 200; i++) {
      const n = roll(`hall:${i}`, { taken: [...BORGES], vocab: VOCAB }).name
      expect(n).toMatch(/^[a-z]{4,10}$/)
      expect(n).not.toMatch(/[aeiou]{3}/)
      names.add(n)
    }
    expect(names.size).toBeGreaterThan(150)
  })
  test("mostly names of their own; a Borges character now and then, as a flavour", () => {
    let borges = 0
    for (let i = 0; i < 400; i++) if ((BORGES as readonly string[]).includes(roll(`hall:${i}`, { taken: [], vocab: VOCAB }).name)) borges++
    expect(borges).toBeGreaterThan(40)
    expect(borges).toBeLessThan(140)
  })
  test("three generators: everyday names, villain names, and Borges", () => {
    const names = Array.from({ length: 400 }, (_, i) => roll(`hall:${i}`, { taken: [], vocab: VOCAB }).name)
    const villain = names.filter((n) => /(x|th|rax|oth)$|^(kr|dr|gr|zh|vr|sk)|ae|au/.test(n)).length
    expect(villain).toBeGreaterThan(40)
    expect(names.filter((n) => !(BORGES as readonly string[]).includes(n)).length).toBeGreaterThan(200)
  })
  test("all names taken → a seeded original name, still legal", () => {
    const c = roll("hall:3", { taken: [...BORGES], vocab: VOCAB })
    expect(c.name).toMatch(LEGAL)
    expect(BORGES as readonly string[]).not.toContain(c.name)
  })
  test("pitch and soul skeleton are deterministic text, drawn=false", () => {
    const c = roll("hall:9", { taken: [], vocab: VOCAB })
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
  const made: string[] = []
  const mk = () => {
    const d = mkdtempSync(join(tmpdir(), "hall-"))
    made.push(d)
    return d
  }
  afterEach(() => {
    for (const d of made.splice(0)) rmSync(d, { recursive: true, force: true })
  })
  const tmp = () => join(mk(), "hall.json")
  test("a hand-edited hall.json whose look is not an object loads without it", () => {
    const p = tmp()
    writeFileSync(p, JSON.stringify({ seed: "hall:1", overrides: { look: "nope", soul: "## Wants\nx\n" } }))
    const h = loadHall(p)
    expect(h.overrides.look).toBeUndefined()
    expect(h.overrides.soul).toBe("## Wants\nx\n")
  })
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
    const p = join(mk(), "a", "b", "hall.json")
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
    const c = roll("hall:2", { taken: [], vocab: VOCAB })
    expect(applyOverrides(roll("hall:2", { taken: [], vocab: VOCAB }), {})).toEqual(c)
  })
  test("overrides replace fields but never the seed", () => {
    const c = applyOverrides(roll("hall:2", { taken: [], vocab: VOCAB }), { name: "zed", grade: "senior", seed: "evil" } as never)
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
    const c = roll("hall:2", { taken: [], vocab: VOCAB })
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
  test("a hand-edited name that is not a soul file's name is dropped, on the card and on the pile", () => {
    const p = tmp()
    writeFileSync(p, JSON.stringify({ seed: "hall:3", locks: {}, overrides: { name: "../x", grade: "senior" }, pile: [{ seed: "hall:2", overrides: { name: "Bad Name" } }, { seed: "hall:4", overrides: { name: "ts-ai-ang" } }] }))
    const h = loadHall(p)
    expect(h.overrides).toEqual({ grade: "senior" })
    expect(h.pile.map((e) => e.overrides)).toEqual([{}, { name: "ts-ai-ang" }])
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
    expect(candidateOf(h, o)).toEqual(applyOverrides(roll("hall:4", o), { grade: "senior" }))
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
  test("a pass past a hire: the locked name is used up, so it is not baked into the next card", () => {
    const h = hall({ seed: "hall:1", locks: { fields: ["name" as const] }, overrides: { name: "uqbar" } })
    const cur = candidateOf(h, o)
    expect(cur.name).toBe("uqbar")
    const taken = [...o.taken, cur.name]
    const next = pass(h, { ...o, taken })
    expect(next.overrides.name).toBeUndefined()
    expect(candidateOf(next, { ...o, taken }).name).not.toBe(cur.name)
    expect(next.locks).toEqual(h.locks)
  })
  test("a pass with no locks drops the previous overrides", () => {
    expect(pass(hall({ overrides: { name: "zed" } }), o).overrides).toEqual({})
  })
  test("maybe puts the current card on the pile, then passes", () => {
    const h = hall({ seed: "hall:1", overrides: { grade: "senior" } })
    const m = maybe(h, o)
    expect(m.pile).toEqual([{ seed: "hall:1", overrides: { grade: "senior", name: candidateOf(h, o).name } }])
    expect(m.seed).toBe("hall:2")
  })
  test("a pile entry re-renders with the name the card showed", () => {
    const bench = ["funes"]
    const h = hall({ seed: "hall:1" })
    const ctx = { ...o, taken: takenNames(h, bench, VOCAB) }
    const shown = candidateOf(h, ctx).name
    const m = maybe(h, ctx)
    const again = candidateOf({ ...m, seed: m.pile[0].seed, overrides: m.pile[0].overrides }, { ...o, taken: takenNames(m, bench, VOCAB) })
    expect(again.name).toBe(shown)
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
    expect(names).toContain(roll("hall:2", { taken: ["funes"], vocab: VOCAB }).name)
  })
  test("toggleLock flips a slot or field and drops empty lists", () => {
    let l = toggleLock({}, "slots", "head")
    expect(l).toEqual({ slots: ["head"] })
    l = toggleLock(l, "fields", "grade")
    expect(l).toEqual({ slots: ["head"], fields: ["grade"] })
    expect(toggleLock(toggleLock(l, "slots", "head"), "fields", "grade")).toEqual({})
  })
})

test("a name seated off shift, or in another workspace, is taken: the hall never offers it", () => {
  const a = {
    bench: [{ name: "tertius" }],
    shifts: [{ name: "tertius" }, { name: "asterion" }, { name: "elsewhere-seat" }],
  }
  expect(seatedNames(a).sort()).toEqual(["asterion", "elsewhere-seat", "tertius"])
  expect(seatedNames({ bench: [{ name: "only" }] })).toEqual(["only"])
})

describe("hall e: edit the card", () => {
  const ctx = (taken: string[] = []) => ({ taken, vocab: VOCAB })
  const h0 = () => ({ ...emptyHall(), seed: "hall:4" })

  test("a text field is stored as an edit over the seed, and the card shows it", () => {
    const r = editField(h0(), ctx(), "name", "ashe-2")
    expect("error" in r).toBe(false)
    const h = r as ReturnType<typeof emptyHall>
    expect(h.seed).toBe("hall:4")
    expect(candidateOf(h, ctx()).name).toBe("ashe-2")
  })
  test("a name must be legal and not taken", () => {
    expect(editField(h0(), ctx(), "name", "Bad Name")).toEqual({ error: expect.stringContaining("name") })
    expect(editField(h0(), ctx(["funes"]), "name", "funes")).toEqual({ error: expect.stringContaining("bench") })
  })
  test("archetype, grade and specialty must come from the roster's vocabulary", () => {
    expect(candidateOf(editField(h0(), ctx(), "grade", "senior") as ReturnType<typeof emptyHall>, ctx()).grade).toBe("senior")
    expect(editField(h0(), ctx(), "grade", "wizard")).toEqual({ error: expect.stringContaining("grade") })
    expect(editField(h0(), ctx(), "archetype", "nope")).toEqual({ error: expect.stringContaining("archetype") })
  })
  test("pitch and soul take any non-blank text; blank is refused", () => {
    const h = editField(editField(h0(), ctx(), "pitch", "Quiet and good.") as ReturnType<typeof emptyHall>, ctx(), "soul", "## Wants\nsleep\n") as ReturnType<typeof emptyHall>
    const c = candidateOf(h, ctx())
    expect(c.pitch).toBe("Quiet and good.")
    expect(c.soul).toBe("## Wants\nsleep\n")
    expect(editField(h0(), ctx(), "pitch", "   ")).toEqual({ error: expect.stringContaining("pitch") })
  })
  test("an edited field survives a pass only when locked, like any other", () => {
    const rolled = roll("hall:5", ctx()).grade, edit = VOCAB.grades.find(g => g !== rolled)!
    const e = editField(h0(), ctx(), "grade", edit) as ReturnType<typeof emptyHall>
    expect(candidateOf(pass(e, ctx()), ctx()).grade).toBe(rolled)
    expect(candidateOf(pass({ ...e, locks: { fields: ["grade"] } }, ctx()), ctx()).grade).toBe(edit)
  })
  test("setLook stores the whole edited look as the look override, hair, dials and all", () => {
    const base = candidateOf(h0(), ctx()).look
    const edited = { ...base, hair: base.hair === "bald" ? "mop" as const : "bald" as const, body: "tall" as const, parts: { head: { id: "x", dials: { n: 2 } } } }
    const h = setLook(h0(), edited as typeof base)
    expect(candidateOf(h, ctx()).look).toEqual(edited)
    expect(JSON.parse(JSON.stringify(h)).overrides.look.parts.head.dials).toEqual({ n: 2 })
  })
  test("a pass drops an edited look unless its slot is locked", () => {
    const base = candidateOf(h0(), ctx()).look
    const edited = { ...base, body: "tall" as const, parts: { head: { id: "x" } } }
    const h = setLook(h0(), edited as typeof base)
    expect(candidateOf(pass(h, ctx()), ctx()).look.body).not.toBe("tall")
    const kept = candidateOf(pass({ ...h, locks: { slots: ["head"] } }, ctx()), ctx())
    expect(kept.look.parts?.head).toEqual({ id: "x" })
  })
})
