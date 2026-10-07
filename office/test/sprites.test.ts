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
