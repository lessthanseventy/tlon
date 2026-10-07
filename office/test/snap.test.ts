import { describe, expect, test } from "bun:test"
import { nearestChar } from "../kit/snap"

describe("nearestChar", () => {
  test("an exact role hex snaps to its own char", () => {
    const paint = { k: "#0A0A0A", y: "#FFB000", p: "#B4A5D6" }
    expect(nearestChar("#FFB000", paint)).toBe("y")
  })
  test("a near-miss snaps to the closest role, not alphabetically first", () => {
    const paint = { k: "#0A0A0A", y: "#FFB000" } // far apart; anything warm-ish goes to y
    expect(nearestChar("#FFA000", paint)).toBe("y")
  })
  test("fully transparent is always the clear char, regardless of colour", () => {
    expect(nearestChar("#FFB000", { k: "#0A0A0A" }, 0)).toBe(".")
  })
})
