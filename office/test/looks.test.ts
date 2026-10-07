import { describe, expect, test } from "bun:test"
import { overrideFor, useLookOverrides } from "../kit/looks"

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
})
