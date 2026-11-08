import { describe, expect, test } from "bun:test"
import { rushOf, seasonOf } from "../kit/daypart"
import { clockFace } from "../kit/eggs"
import { moment } from "../kit/sim"

const at = (m: number, d: number, h = 15, min = 0, s = 0) => new Date(2026, m, d, h, min, s)

describe("rushOf", () => {
  test("lunch from 12:00 to 12:30, leaving from 17:30 to 18:00, nothing else", () => {
    expect(rushOf(at(5, 3, 11, 59))).toBeNull()
    expect(rushOf(at(5, 3, 12, 0))).toBe("lunch")
    expect(rushOf(at(5, 3, 12, 29))).toBe("lunch")
    expect(rushOf(at(5, 3, 12, 30))).toBeNull()
    expect(rushOf(at(5, 3, 17, 29))).toBeNull()
    expect(rushOf(at(5, 3, 17, 30))).toBe("leaving")
    expect(rushOf(at(5, 3, 18, 0))).toBeNull()
  })
})

describe("seasonOf", () => {
  test("months, and the two days that outrank them", () => {
    expect(seasonOf(at(2, 1))).toBe("spring")
    expect(seasonOf(at(4, 31))).toBe("spring")
    expect(seasonOf(at(5, 1))).toBe("summer")
    expect(seasonOf(at(7, 31))).toBe("summer")
    expect(seasonOf(at(8, 1))).toBeNull()
    expect(seasonOf(at(9, 31))).toBeNull()
    expect(seasonOf(at(11, 25))).toBeNull()
    expect(seasonOf(at(2, 14))).toBe("pi")
    expect(seasonOf(at(11, 31))).toBe("nye")
    expect(seasonOf(at(0, 31))).toBeNull()
  })
})

describe("the lunch rush pulls the kitchen", () => {
  test("coffee, cooler and the machine outweigh the rest at lunch, and only then", () => {
    for (const k of ["cooler", "coffee", "vending"]) {
      expect(moment(k, 12, undefined, false, true)).toBeGreaterThan(moment(k, 12))
      expect(moment(k, 12, undefined, false, false)).toBe(moment(k, 12))
    }
    expect(moment("pool", 12, undefined, false, true)).toBe(moment("pool", 12))
  })
})

describe("Pi Day on the clock face", () => {
  test("3.14 for the first half of each minute on 14 March, the time for the rest", () => {
    expect(clockFace(at(2, 14, 10, 20, 5))).toBe("3.14")
    expect(clockFace(at(2, 14, 10, 20, 45))).toBe("10:20")
    expect(clockFace(at(2, 15, 10, 20, 5))).toBe("10:20")
    expect(clockFace(at(2, 14, 3, 14, 5))).toBe("π")
  })
})
