import { describe, expect, test } from "bun:test"
import { mulberry32 as rng } from "../kit/rng"
import { CAT_BASE, destWeights, pickDest, type Dest, type Temperament } from "../kit/temperament"

const T = (warmth: number, wits: number, energy: number): Temperament => ({ warmth, wits, energy })
const DESTS = Object.keys(CAT_BASE) as Dest[]

function share(t: Temperament, n = 10_000) {
  const r = rng(7), hits = Object.fromEntries(DESTS.map((d) => [d, 0])) as Record<Dest, number>
  for (let i = 0; i < n; i++) hits[pickDest(t, r())]++
  return Object.fromEntries(DESTS.map((d) => [d, hits[d] / n])) as Record<Dest, number>
}

describe("destWeights", () => {
  test("a neutral temperament is exactly today's table", () => {
    const w = destWeights(T(0, 0, 0))
    for (const d of DESTS) expect(w[d]).toBeCloseTo(CAT_BASE[d], 12)
  })
  test("always sums to 1 and stays positive across the whole cube", () => {
    for (const w of [-2, 0, 2]) for (const i of [-2, 0, 2]) for (const e of [-2, 0, 2]) {
      const ws = destWeights(T(w, i, e)), sum = Object.values(ws).reduce((a, b) => a + b, 0)
      expect(sum).toBeCloseTo(1, 10)
      for (const v of Object.values(ws)) expect(v).toBeGreaterThan(0)
    }
  })
})

describe("over 10k ticks the table moves the way the design says", () => {
  test("energy: lazy naps more and plays less than playful", () => {
    const lazy = share(T(0, 0, -2)), playful = share(T(0, 0, 2))
    expect(lazy.nap).toBeGreaterThan(playful.nap + 0.1)
    expect(playful.play).toBeGreaterThan(lazy.play + 0.05)
    expect(playful.perch).toBeGreaterThan(lazy.perch)
  })
  test("wits: dim wanders (spots) more than sharp", () => {
    expect(share(T(0, -2, 0)).spot).toBeGreaterThan(share(T(0, 2, 0)).spot + 0.05)
  })
  test("warmth leaves the table alone", () => {
    const a = share(T(-2, 0, 0)), b = share(T(2, 0, 0))
    for (const d of DESTS) expect(a[d]).toBe(b[d])
  })
  test("the empirical share tracks the weights", () => {
    const t = T(1, -1, 2), w = destWeights(t), s = share(t)
    for (const d of DESTS) expect(Math.abs(s[d] - w[d])).toBeLessThan(0.02)
  })
})
