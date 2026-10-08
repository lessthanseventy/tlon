import { describe, expect, test } from "bun:test"
import { bucketFor, NINA, SWEET } from "../kit/voices"

const W = (warmth: number) => ({ warmth, wits: 0, energy: 0 })

describe("bucketFor", () => {
  test("warm goes sweet nearly always, 10k draws", () => {
    let sweet = 0, s = 1
    const r = () => ((s = (s * 48271) % 2147483647) / 2147483647)
    for (let i = 0; i < 10_000; i++) if (bucketFor("pet", W(2), r) === SWEET.pet) sweet++
    expect(sweet / 10_000).toBeGreaterThan(0.85)
  })
  test("neutral and cold warmth never go sweet — an unset temperament is today's Nina", () => {
    for (const w of [0, -1, -2]) for (let i = 0; i < 200; i++) expect(bucketFor("pet", W(w), Math.random)).toBe(NINA.pet)
  })
  test("an occasion with no sweet bucket falls back to NINA's", () => {
    expect(bucketFor("web", W(2), () => 0)).toBe(NINA.web)
  })
})
