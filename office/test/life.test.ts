import { describe, expect, test } from "bun:test"
import { bedScene, homeLevel, lifeBar, lifeHeader, lifeRows, streakFrames } from "../kit/life"
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

describe("lifeRows", () => {
  const s = { xp: 650, level: 2, next_level_at: 900, streaks: { "1": 3 },
    due: [{ routine_id: 1, title: "teeth", due_at: "2026-10-08T07:00:00Z", window_remaining: 600 },
          { routine_id: 2, title: "stretch", due_at: "2026-10-08T09:00:00Z", window_remaining: -60 }],
    quests: [{ id: 5, title: "book dentist", due_at: null, xp: 20 }], today: [] }
  test("due routines first (overdue flagged), then open quests", () => {
    expect(lifeRows(s).map((r) => [r.kind, r.id, r.text])).toEqual([
      ["routine", 2, "stretch · overdue"],
      ["routine", 1, "teeth · 10m left · streak 3"],
      ["quest", 5, "book dentist · +20 xp"],
    ])
  })
})

describe("homeLevel", () => {
  const w = (level: number) => ({ level, xp: 0, due: [] })
  test("the highest level among home workspaces", () =>
    expect(homeLevel({ ...EMPTY, life: { "7": w(2), "8": w(5) } })).toBe(5))
  test("null with no life side", () => {
    expect(homeLevel(EMPTY)).toBeNull()
    expect(homeLevel({ ...EMPTY, life: {} })).toBeNull()
  })
})

describe("streakFrames", () => {
  test("a streak under 7 hangs no frame", () => expect(streakFrames({ "1": 3 })).toEqual([]))
  test("a broken streak hangs no frame", () => expect(streakFrames({ "1": 0 })).toEqual([]))
  test("7 hangs a tier 1 frame for its routine", () =>
    expect(streakFrames({ "1": 7 })).toEqual([{ routine: 1, tier: 1 }]))
  test("30 is tier 2, the highest milestone reached", () =>
    expect(streakFrames({ "4": 45 })).toEqual([{ routine: 4, tier: 2 }]))
  test("100 is tier 3", () => expect(streakFrames({ "9": 100 })).toEqual([{ routine: 9, tier: 3 }]))
  test("one frame per routine that has reached a milestone, in routine order", () =>
    expect(streakFrames({ "2": 2, "8": 7, "5": 30 })).toEqual([{ routine: 5, tier: 2 }, { routine: 8, tier: 1 }]))
})

describe("bedScene", () => {
  const at = (iso: string) => Date.parse(iso)
  const today = (done: boolean) => [
    { routine_id: 1, title: "teeth", due_at: "2026-10-22T07:00:00Z", done: false },
    { routine_id: 2, title: "in bed by 23:00", due_at: "2026-10-22T23:00:00Z", done },
  ]
  test("a stamped bed routine puts you asleep", () => expect(bedScene(today(true), at("2026-10-22T22:00:00Z"))).toBe("asleep"))
  test("past its time and unstamped, the cat is already on the bed", () =>
    expect(bedScene(today(false), at("2026-10-22T23:30:00Z"))).toBe("cat"))
  test("before its time and unstamped, the bed is empty", () => expect(bedScene(today(false), at("2026-10-22T20:00:00Z"))).toBeNull())
  test("no bed routine, no scene — other routines don't count", () =>
    expect(bedScene([{ routine_id: 1, title: "teeth", due_at: "2026-10-22T07:00:00Z", done: true }], at("2026-10-22T23:30:00Z"))).toBeNull())
})
