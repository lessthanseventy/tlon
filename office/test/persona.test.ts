import { expect, test } from "bun:test"
import { personaLines, type Persona } from "../kit/persona"

const p: Persona = { seed: 7, source: "model", voice: "dry", backstory: "Grew up above a clockmaker's.", quirks: { desk_object: "a mug", hobby: "chess", catchphrase: "Noted.", pet_peeve: "tabs" } }

test("a persona reads as a backstory, a voice and the four quirks", () => {
  const l = personaLines(p, 60)
  expect(l.join("\n")).toContain("Grew up above a clockmaker's.")
  expect(l).toContain("voice: dry")
  expect(l).toContain("desk: a mug")
  expect(l).toContain("hobby: chess")
  expect(l).toContain('says: "Noted."')
  expect(l).toContain("peeve: tabs")
})

test("a fallback or edited persona says so", () => {
  expect(personaLines({ ...p, source: "fallback" }, 60).at(-1)).toContain("handwritten")
  expect(personaLines({ ...p, edited: true }, 60).at(-1)).toContain("edited")
})

test("no persona is no lines", () => {
  expect(personaLines(null, 60)).toEqual([])
})

test("the backstory wraps to the width", () => {
  const l = personaLines({ ...p, backstory: "word ".repeat(30) }, 30)
  expect(l.every((x) => x.length <= 30)).toBe(true)
})
