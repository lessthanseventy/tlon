import { expect, test } from "bun:test"
import { personCard } from "../tui/person-card"
import { parseSoul } from "../kit/souls"
import type { Persona } from "../kit/persona"
import { KEYS } from "../tui/keys"

const persona: Persona = { seed: 7, source: "model", voice: "dry", backstory: "Grew up above a clockmaker's.", quirks: { desk_object: "a mug", hobby: "chess", catchphrase: "Noted.", pet_peeve: "tabs" } }
const soul = parseSoul("## Where they're from\nLisbon.\n\n## Wants\nA quiet desk.\n\n## Diary\n" + Array.from({ length: 40 }, (_, i) => `day ${i}`).join("\n"))

test("closed, the card is at most one line, so the conversation stays the body", () => {
  expect(personCard(soul, persona, 60, false).length).toBe(1)
  expect(personCard(undefined, persona, 60, false).length).toBe(1)
  expect(personCard(soul, undefined, 60, false).length).toBe(1)
  expect(personCard(undefined, undefined, 60, false)).toEqual([])
})

test("closed, the one line is dim and names the key that opens the rest", () => {
  const [l] = personCard(soul, persona, 60, false)
  expect(l!.tone).toBe("dim")
  expect(l!.text).toContain("Grew up above a clockmaker's.")
  expect(l!.text).toContain("(space)")
})

test("open, the card holds the whole soul and persona", () => {
  const text = personCard(soul, persona, 60, true).map((l) => l.text).join("\n")
  for (const s of ["soul", "Wants", "A quiet desk.", "day 39", "voice: dry", "hobby: chess", "seed 7"]) expect(text).toContain(s)
})

test("the toggle is a person bind", () => {
  expect(KEYS.find((b) => b.id === "person.space")?.scope).toBe("card:person")
})
