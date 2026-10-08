import { describe, expect, test } from "bun:test"
import { lifeBar, lifeHeader } from "../kit/life"
import { EMPTY } from "../kit/types"

describe("lifeBar", () => {
  // level 2 starts at 400, level 3 at 900 (100·L²): 650 is halfway through level 2
  test("empty at the start of a level", () => expect(lifeBar(400, 400, 900)).toBe("▱▱▱▱▱"))
  test("half-way rounds down to 2 of 5", () => expect(lifeBar(650, 400, 900)).toBe("▰▰▱▱▱"))
  test("never over, even past the next level", () => expect(lifeBar(1200, 400, 900)).toBe("▰▰▰▰▰"))
})
describe("lifeHeader", () => {
  const a = { ...EMPTY, life: { "7": { level: 2, xp: 650, due: [{ routine_id: 1, title: "teeth", due_at: "2026-10-08T07:00:00Z", window_remaining: 600 }] } } }
  test("level, bar, due count — for a workspace that has a life entry", () =>
    expect(lifeHeader(a, 7)).toBe("lv 2 ▰▰▱▱▱ · 1 due"))
  test("nothing due says so", () =>
    expect(lifeHeader({ ...a, life: { "7": { level: 2, xp: 650, due: [] } } }, 7)).toBe("lv 2 ▰▰▱▱▱ · all done"))
  test("a workspace with no life entry has no header", () => {
    expect(lifeHeader(a, 8)).toBeNull()
    expect(lifeHeader(a, null)).toBeNull()
  })
})
