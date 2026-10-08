import { expect, test } from "bun:test"
import { EMPTY, flagOn } from "../kit/types"

test("a flag is on only when the snapshot says so; one it doesn't name, or no flags at all, is off", () => {
  const all = { ...EMPTY, ok: true, flags: { build_mode: true, other: false } }
  expect(flagOn(all, "build_mode")).toBe(true)
  expect(flagOn(all, "other")).toBe(false)
  expect(flagOn(all, "nope")).toBe(false)
  expect(flagOn(EMPTY, "build_mode")).toBe(false)
})
