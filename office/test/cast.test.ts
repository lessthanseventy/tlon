import { expect, test } from "bun:test"
import { CAST_FIELDS, EDITABLE_HERE, castRows, nextTrait, rerollTrait } from "../tui/cast"

const vocab = { archetypes: ["builder", "reviewer"], grades: ["junior", "senior", "greybeard"], specialties: ["office", "server"] }
const seat = (name: string, extra = {}) => ({ name, archetype: "builder", model: null, voice: null, hasSoul: false, hasLook: false, ...extra })

test("one row per seat, one cell per field, in the spec's order", () => {
  const rows = castRows([seat("ada"), seat("bo")], {})
  expect(rows.map(r => r.name)).toEqual(["ada", "bo"])
  expect(rows[0]!.cells.map(c => c.field)).toEqual([...CAST_FIELDS])
})
test("name and archetype are read-only; the rest are editable", () => {
  const cells = castRows([seat("ada")], {})[0]!.cells
  expect(cells.filter(c => !c.editable).map(c => c.field)).toEqual(["name", "archetype"])
  expect([...EDITABLE_HERE]).toEqual(["look", "soul", "voice", "grade", "specialty", "model"])
})
test("grade and specialty come from cast.json, else say unset", () => {
  const cells = castRows([seat("ada")], { ada: { grade: "senior" } })[0]!.cells
  expect(cells.find(c => c.field === "grade")!.value).toBe("senior")
  expect(cells.find(c => c.field === "specialty")!.value).toBe("unset")
})
test("voice, model, soul and look read as words", () => {
  const cells = castRows([seat("ada", { voice: "dry", model: "opus", hasSoul: true, hasLook: true })], {})[0]!.cells
  const v = (f: string) => cells.find(c => c.field === f)!.value
  expect([v("voice"), v("model"), v("soul"), v("look")]).toEqual(["dry", "opus", "has a soul", "custom look"])
})
test("nextTrait cycles the vocabulary and wraps; an unknown current starts at the first", () => {
  expect(nextTrait(vocab.grades, "junior")).toBe("senior")
  expect(nextTrait(vocab.grades, "greybeard")).toBe("junior")
  expect(nextTrait(vocab.grades, "unset")).toBe("junior")
})
test("rerollTrait is deterministic, in the vocabulary, and reads the hall's own pick", () => {
  const a = rerollTrait("ada:1", "grade", vocab), b = rerollTrait("ada:1", "grade", vocab)
  expect(a).toBe(b)
  expect(vocab.grades).toContain(a)
  expect(vocab.specialties).toContain(rerollTrait("ada:1", "specialty", vocab))
})
