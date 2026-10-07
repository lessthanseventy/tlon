import { describe, expect, test } from "bun:test"
import { looksGen, overrideFor, useLookOverrides } from "../kit/looks"

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
