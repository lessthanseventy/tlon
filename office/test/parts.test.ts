import { describe, expect, test } from "bun:test"
import { contrast, ROLE } from "../kit/palette"
import { dialsOf, gearOf, idsIn, nextPart, PARTS, PART_IDS, SLOTS, type DialVals, type Slot } from "../kit/parts"
import { BODIES, figure, heightOf, lookOf, paints, rollLook, type Dir, type Look } from "../kit/sprites"

/** every combination of a part's dials */
function combos(id: string): DialVals[] {
  return Object.entries(PARTS[id]!.dials).reduce<DialVals[]>((acc, [k, opts]) => acc.flatMap((a) => opts.map((o) => ({ ...a, [k]: o }))), [{}])
}
// the letters a slot may paint: outside the body they sit on the room, so only roles that clear 3:1
const LETTERS: Record<Slot, string> = { head: "rgywc_.", neck: "rgywc.", back: "rgywc.", hand: "rgywc.", eyes: "kgryw.", mouth: "h." }

describe("the parts library is well-formed", () => {
  test("every slot has parts, and every part names its slot", () => {
    for (const s of SLOTS) expect(idsIn(s).length).toBeGreaterThanOrEqual(2)
    expect(PART_IDS.length).toBeGreaterThanOrEqual(21)
  })
  test("every part, at every dial setting, has all three views of 12-wide rows on real row numbers, in its slot's letters", () => {
    for (const id of PART_IDS) for (const d of combos(id)) {
      const g = PARTS[id]!.draw(d), ok = new RegExp(`^[${LETTERS[PARTS[id]!.slot]!.replace(".", "\\.")}]{12}$`)
      for (const view of ["front", "side", "back"] as const) {
        expect(g[view]).toBeDefined()
        for (const [row, s] of Object.entries(g[view])) {
          const n = Number(row)
          expect({ id, d, view, row, ok: Number.isInteger(n) && n >= 0 && n <= 17 && s!.length === 12 && ok.test(s!) }).toMatchObject({ ok: true })
        }
      }
    }
  })
  test("each part draws something in the front and side views", () => {
    for (const id of PART_IDS) for (const view of ["front", "side"] as const) expect(Object.keys(PARTS[id]!.draw(dialsOf(PARTS[id]!, {}))[view]).length).toBeGreaterThan(0)
  })
  test("the paint letters clear 3:1 on every room background, like the skin roles", () => {
    const paint = paints("#fff", lookOf("x"))
    for (const slot of ["head", "neck", "back", "hand"] as const) for (const ch of LETTERS[slot].replace(/[._]/g, "")) {
      for (const bg of [ROLE.ground, ROLE.panel, ROLE.raised, ROLE.edge]) expect({ slot, ch, ok: contrast(paint[ch]!, bg) >= 3 }).toMatchObject({ ok: true })
    }
  })
  test("the default glasses are today's glasses", () => {
    expect(gearOf({ id: "glasses" })!.front[6]).toBe("..kk..kk....")
    expect(gearOf({ id: "glasses" })!.side[6]).toBe(".kk.........")
  })
})

describe("dials", () => {
  test("a missing or unoffered dial value falls back to the first option", () => {
    expect(dialsOf(PARTS.tophat!, { crown: 3, brim: 99 })).toEqual({ hue: "r", crown: 3, brim: 10, band: "none" })
  })
  test("a dial changes the pixels", () => {
    expect(gearOf({ id: "tophat", dials: { crown: 3 } })!.front).not.toEqual(gearOf({ id: "tophat", dials: { crown: 2 } })!.front)
    expect(gearOf({ id: "cape", dials: { length: "long" } })!.back).not.toEqual(gearOf({ id: "cape" })!.back)
  })
  test("an id the library no longer has draws nothing instead of throwing", () => {
    expect(gearOf({ id: "gone" })).toBeUndefined()
    expect(() => figure({ ...lookOf("yu"), parts: { head: { id: "gone" } } }, null, false, false, "down", "stand", 0, false)).not.toThrow()
  })
  test("nextPart walks a slot's parts, then none, then round again", () => {
    const seen: (string | undefined)[] = []
    let cur = nextPart("head", undefined)
    for (let i = 0; i < 20 && cur; i++) { seen.push(cur.id); cur = nextPart("head", cur) }
    expect(seen).toEqual(idsIn("head"))
    expect(nextPart("head", undefined)!.id).toBe(idsIn("head")[0]!)
  })
})

describe("a part on a figure", () => {
  const draw = (look: Look, face: Dir = "down") => figure(look, null, false, false, face, "stand", 0, false)
  test("a hat clears the hair tips under it and paints over the brim row", () => {
    const bare = draw({ ...lookOf("ashe"), hair: "spiky" }), hatted = draw({ ...lookOf("ashe"), hair: "spiky", parts: { head: { id: "tophat" } } })
    expect(bare[1]).toContain("h")
    expect(hatted[1]).not.toContain("h")
    expect(hatted[3]).toBe(".rrrrrrrrrr.")
  })
  test("a cape is behind the body from the front and over it from behind", () => {
    const l = { ...lookOf("yu"), parts: { back: { id: "cape" } } } satisfies Look
    expect(draw(l)[10]).toBe("r.ssssssss.r")
    expect(draw(l, "up")[10]).toBe(".rrrrrrrrrr.")
  })
  test("parts are worn together, one per slot", () => {
    const l: Look = { ...lookOf("yu"), parts: { head: { id: "beanie" }, eyes: { id: "monocle" }, mouth: { id: "beard" }, neck: { id: "scarf" }, back: { id: "wings" }, hand: { id: "mug" } } }
    const worn = draw(l), bare = draw(lookOf("yu"))
    expect(worn.filter((r, i) => r !== bare[i]).length).toBeGreaterThanOrEqual(8)
  })
  test("the hand and neck parts mirror with the figure facing right", () => {
    const l: Look = { ...lookOf("yu"), parts: { hand: { id: "wand" } } }
    expect(draw(l, "right")[13]).toBe([...draw(l, "left")[13]!].reverse().join(""))
  })
})

describe("a seeded roll", () => {
  test("is the same for the same seed, and varied across seeds", () => {
    expect(rollLook("a")).toEqual(rollLook("a"))
    const ids = new Set<string>(), bodies = new Set<string>()
    for (let i = 0; i < 200; i++) { const r = rollLook(`seed${i}`); bodies.add(r.body!); for (const p of Object.values(r.parts!)) ids.add(p.id) }
    expect(bodies.size).toBe(BODIES.length)
    expect(ids.size).toBe(PART_IDS.length)
  })
  test("renders every view, pose and walk frame at the right height", () => {
    for (let i = 0; i < 100; i++) {
      const look: Look = { ...lookOf(`n${i}`), ...rollLook(`seed${i}`) }
      for (const face of ["down", "up", "left", "right"] as const) for (const step of [0, 1, 2]) {
        const f = figure(look, null, false, false, face, "stand", step, false)
        expect(f.length).toBe(heightOf(look))
        expect(f.every((r) => /^[a-z.]{12}$/.test(r))).toBe(true)
        expect(figure(look, null, false, false, face, "sit", step, false).length).toBe(14)
      }
    }
  })
})
