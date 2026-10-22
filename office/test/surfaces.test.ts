import { describe, expect, test } from "bun:test"
import { phoneBar, ringFrame } from "../kit/surfaces"

describe("the phone in the top bar", () => {
  test("nothing owed is no segment at all", () => {
    expect(phoneBar({ phone: 0 })).toBeNull()
  })
  test("an answer owed is the one count, ringing", () => {
    expect(phoneBar({ phone: 3 })).toEqual({ text: "3 waiting on you", ringing: true })
  })
  test("ringing changes the glyph, so it is never colour alone; quiet holds still", () => {
    expect(new Set([0, 1, 2, 3].map((t) => ringFrame(t, true))).size).toBeGreaterThanOrEqual(2)
    expect(new Set([0, 1, 2, 3].map((t) => ringFrame(t, false))).size).toBe(1)
  })
})
