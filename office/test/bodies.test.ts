import { describe, expect, test } from "bun:test"
import { BODIES, figure, heightOf, lookOf, type Look } from "../kit/sprites"

describe("body shapes", () => {
  const look = (body: Look["body"]): Look => ({ ...lookOf("yu"), body })
  test("tall and short change only the legs; every shape is 12 wide", () => {
    const avg = figure(look("average"), null, false, false, "down", "stand", 0, false)
    expect(avg.length).toBe(20)
    for (const [b, h] of [["tall", 22], ["short", 18], ["round", 20]] as const) {
      const f = figure(look(b), null, false, false, "down", "stand", 0, false)
      expect(f.length).toBe(h)
      expect(heightOf(look(b))).toBe(h)
      expect(f.every((r) => r.length === 12)).toBe(true)
      if (b !== "round") expect(f.slice(0, 15)).toEqual(avg.slice(0, 15))
    }
    expect(figure(look("round"), null, false, false, "down", "stand", 0, false)[11]).toContain("ssssssssssss")
  })
  test("every shape draws every view and walk frame at its height, seated at 14", () => {
    for (const b of BODIES) for (const face of ["down", "up", "left", "right"] as const) for (const step of [0, 1, 2]) {
      expect(figure(look(b), "builder", true, false, face, "stand", step, false).length).toBe(heightOf(look(b)))
      expect(figure(look(b), null, false, false, face, "sit", step, false).length).toBe(14)
    }
  })
  test("a custom look keeps the average build", () => {
    expect(heightOf({ ...look("tall"), custom: { front: Array(20).fill(".".repeat(12)) } })).toBe(20)
  })
})
