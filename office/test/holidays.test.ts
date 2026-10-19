import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { newYearLeft, Tv } from "../kit/tv"
import { WideRoom, WIDE_H, zones } from "../rooms/wide"
import { geometry, measureFor } from "../tui/paint"
import { focus, office, seeded } from "./golden"

const at = (m: number, d: number, h = 15, min = 0, s = 0) => new Date(2026, m, d, h, min, s)
const frame = (when: Date) => {
  const a = viewOf(office(2), 1)
  const g = geometry(696, WIDE_H, 220, 70, 8, { w: 8, h: 16 }, true)
  return new WideRoom(696).render(a, focus, measureFor(g), when)
}

describe("Feb 14: one valentine on the corkboard", () => {
  test("only that day, and it is a note you can read", () => seeded(3, () => {
    const day = frame(at(1, 14)), before = frame(at(1, 13)), after = frame(at(1, 15))
    const tips = (f: ReturnType<typeof frame>) => f.hits.filter((h) => h.tip?.startsWith("a valentine"))
    expect(tips(day)).toHaveLength(1)
    expect(tips(before)).toHaveLength(0)
    expect(tips(after)).toHaveLength(0)
    expect(Buffer.from(day.rgba).equals(Buffer.from(before.rgba))).toBe(false)
  }))
  test("the same frame at the same frozen clock, twice", () => seeded(3, () => {
    expect(Buffer.from(frame(at(1, 14)).rgba).equals(Buffer.from(frame(at(1, 14)).rgba))).toBe(true)
  }))
})

describe("New Year's Eve: the countdown channel", () => {
  test("it runs from 23:50 on Dec 31 to midnight, and only then", () => {
    expect(newYearLeft(at(11, 31, 23, 49, 59))).toBeNull()
    expect(newYearLeft(at(11, 31, 23, 50, 0))).toBe(600)
    expect(newYearLeft(at(11, 31, 23, 59, 59))).toBe(1)
    expect(newYearLeft(at(0, 1, 0, 0, 0))).toBeNull()
    expect(newYearLeft(at(11, 30, 23, 55))).toBeNull()
    expect(newYearLeft(at(5, 30, 23, 55))).toBeNull()
  })
  test("the TV counts down the seconds it is given, takes over from the show, and hands back", () => {
    const tv = new Tv(48, 28), shown = tv.channel
    tv.setCountdown(125)
    tv.step()
    expect(tv.channel).toBe("countdown")
    const two05 = tv.screen.dots.join("")
    expect(tv.screen.dots.filter((d) => d > 0).length).toBeGreaterThan(30)
    tv.setCountdown(124)
    tv.step()
    expect(tv.screen.dots.join("")).not.toBe(two05)
    tv.setCountdown(null)
    expect(tv.channel).toBe(shown)
  })
  test("the wide room follows its own clock: the channel is up at 23:55 on Dec 31 and not an hour earlier", () => seeded(3, () => {
    const channel = (when: Date) => {
      const room = new WideRoom(560), a = viewOf(office(2), 1)
      room.setClock(() => when)
      for (let i = 0; i < 6; i++) room.step(a)
      return (room as unknown as { tvSet: Tv }).tvSet.channel
    }
    expect(channel(at(11, 31, 23, 55))).toBe("countdown")
    expect(channel(at(11, 31, 22, 55))).not.toBe("countdown")
    expect(channel(at(0, 1, 0, 5))).not.toBe("countdown")
  }))
})

describe("the room's seasonal decor keeps its windows", () => {
  // the lounge corner where October's lanterns and December's tree stand, hashed from the frame
  const corner = (when: Date) => {
    const f = frame(when), { L0 } = zones(696), rows: number[] = []
    for (let y = 135; y < 152; y++) for (let x = L0 + 40; x < L0 + 52; x++) rows.push(...f.rgba.subarray((y * f.width + x) * 4, (y * f.width + x) * 4 + 4))
    return rows.join(",")
  }
  test("decorated across all of October and December, bare either side and in between", () => seeded(3, () => {
    const bare = corner(at(2, 10))
    for (const [m, d] of [[8, 30], [10, 1], [10, 30], [0, 1], [1, 14], [4, 1]] as const) expect(corner(at(m, d)), `${m + 1}/${d}`).toBe(bare)
    for (const [m, d] of [[9, 1], [9, 31], [11, 1], [11, 31]] as const) expect(corner(at(m, d)), `${m + 1}/${d}`).not.toBe(bare)
  }))
})
