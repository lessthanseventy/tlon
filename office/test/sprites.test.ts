import { describe, expect, test } from "bun:test"
import { lookOf, paints } from "../kit/sprites"
import { ROLE } from "../kit/palette"

describe("paints", () => {
  test("skin (f) is ROLE.prose when the look has no skinRole", () => {
    expect(paints("#fff", lookOf("hronir")).f).toBe(ROLE.prose)
  })
  test("skin (f) follows look.skinRole when set", () => {
    expect(paints("#fff", { ...lookOf("hronir"), skinRole: "builder" }).f).toBe(ROLE.builder)
  })
})
