import { describe, expect, test } from "bun:test"
import { figure, HAIR_STYLES, lookOf, OUTFIT } from "../kit/sprites"

describe("more hair and outfits", () => {
  test("every style draws in every view, 12 wide, and the new ones differ from the old", () => {
    for (const h of HAIR_STYLES) for (const face of ["down", "up", "left"] as const) {
      const f = figure({ ...lookOf("x"), hair: h }, null, false, false, face, "stand", 0, false)
      expect(f.length).toBe(20)
      expect(f.every((r) => r.length === 12)).toBe(true)
    }
    const front = HAIR_STYLES.map((h) => figure({ ...lookOf("x"), hair: h }, null, false, false, "down", "stand", 0, false).slice(0, 6).join())
    expect(new Set(front).size).toBe(HAIR_STYLES.length)
  })
  test("every outfit has three views of 12-wide rows on the neck and torso rows", () => {
    for (const o of Object.values(OUTFIT)) for (const v of [o.front, o.side, o.back]) {
      expect(v).toBeDefined()
      for (const [r, s] of Object.entries(v!)) expect(Number(r) >= 9 && Number(r) <= 14 && s!.length === 12).toBe(true)
    }
  })
})
