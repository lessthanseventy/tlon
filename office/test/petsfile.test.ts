import { afterAll, describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { loadPets, savePets } from "../tui/pets"

const dir = mkdtempSync(join(tmpdir(), "pets-"))
afterAll(() => rmSync(dir, { recursive: true, force: true }))

describe("pets.json", () => {
  test("savePets then loadPets round-trips an override", () => {
    const path = join(dir, "a/pets.json")
    savePets({ cat: { name: "Mimi", temperament: "zen" } }, path)
    expect(loadPets(path)).toEqual({ cat: { name: "Mimi", temperament: "zen" } })
  })
  test("savePets merges into what is there, so only the change is written", () => {
    const path = join(dir, "b.json")
    savePets({ cat: { name: "Mimi" } }, path)
    savePets({ cat: { temperament: "zen" } }, path)
    expect(loadPets(path)).toEqual({ cat: { name: "Mimi", temperament: "zen" } })
  })
  test("absent or garbage is undefined", () => {
    const bad = join(dir, "bad.json")
    writeFileSync(bad, "{nope")
    expect(loadPets(join(dir, "none.json"))).toBeUndefined()
    expect(loadPets(bad)).toBeUndefined()
  })
})
