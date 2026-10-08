import { describe, expect, test } from "bun:test"
import { looksGen, overrideFor, trimCustom, useLookOverrides } from "../kit/looks"

describe("look overrides", () => {
  test("nobody is overridden until useLookOverrides is called", () => {
    expect(overrideFor("nobody-set-yet")).toBeUndefined()
  })
  test("useLookOverrides replaces the whole table", () => {
    useLookOverrides({ yu: { skinRole: "builder" } })
    expect(overrideFor("yu")).toEqual({ skinRole: "builder" })
    expect(overrideFor("hronir")).toBeUndefined()
    useLookOverrides({})
    expect(overrideFor("yu")).toBeUndefined()
  })
  test("looksGen advances on every call, so a reader can skip recomputing when it hasn't", () => {
    const g = looksGen()
    useLookOverrides({})
    expect(looksGen()).toBe(g + 1)
  })
})

describe("trimCustom", () => {
  const blank = Array.from({ length: 22 }, () => ".".repeat(12))
  const drawn = blank.map((r, i) => (i === 3 ? "..hh........" : r))
  test("a front-only draw saves only the front", () => {
    expect(trimCustom({ front: drawn, side: blank, back: blank })).toEqual({ front: drawn })
  })
  test("nothing drawn saves no custom field at all", () => {
    expect(trimCustom({ front: blank, side: blank, back: blank })).toBeUndefined()
  })
})
