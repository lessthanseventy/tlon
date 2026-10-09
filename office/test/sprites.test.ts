import { describe, expect, test } from "bun:test"
import { figure, lookOf, paints } from "../kit/sprites"
import { ROLE } from "../kit/palette"

describe("paints", () => {
  test("skin (f) is ROLE.prose when the look has no skinRole", () => {
    expect(paints("#fff", lookOf("hronir")).f).toBe(ROLE.prose)
  })
  test("skin (f) follows look.skinRole when set", () => {
    expect(paints("#fff", { ...lookOf("hronir"), skinRole: "builder" }).f).toBe(ROLE.builder)
  })
})

describe("outfit and accessory overlays", () => {
  test("an outfit overlays the torso row, front view", () => {
    const base = figure(lookOf("hronir"), null, false, false, "down", "stand", 0, false)
    const dressed = figure({ ...lookOf("hronir"), outfit: "hoodie" }, null, false, false, "down", "stand", 0, false)
    expect(dressed[10]).not.toBe(base[10])
    expect(dressed[10]).toBe(".oooooooooo.")
  })
  test("no outfit/accessory set renders exactly as before (regression)", () => {
    expect(figure(lookOf("yu"), "builder", true, false, "down", "stand", 0, false))
      .toEqual(figure(lookOf("yu"), "builder", true, false, "down", "stand", 0, false))
  })
})

describe("archetype gear", () => {
  test("the librarian carries a book, so it isn't a default figure", () => {
    for (const dir of ["down", "left"] as const) {
      const plain = figure(lookOf("quain"), null, false, false, dir, "stand", 0, false)
      expect(figure(lookOf("quain"), "librarian", false, false, dir, "stand", 0, false)).not.toEqual(plain)
    }
  })
})

describe("custom sprite override", () => {
  test("a custom view replaces the generated base but keeps gear and the sit/mirror rules", () => {
    const custom = { front: Array.from({ length: 20 }, (_, i) => (i === 0 ? "kkkkkkkkkkkk" : "............")) }
    const rows = figure({ ...lookOf("hronir"), custom }, "builder", false, false, "down", "stand", 0, false)
    expect(rows[0]).toBe("kkkkkkkkkkkk")
    const sitting = figure({ ...lookOf("hronir"), custom }, null, false, false, "down", "sit", 0, false)
    expect(sitting.length).toBe(14)
    const right = figure({ ...lookOf("hronir"), custom: { side: custom.front } }, null, false, false, "right", "stand", 0, false)
    expect(right[0]).toBe([...custom.front[0]!].reverse().join(""))
  })
})
