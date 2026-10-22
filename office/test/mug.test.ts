import { describe, expect, test } from "bun:test"
import { drawActors, Scene } from "../kit/draw"
import type { Actor } from "../kit/sim"
import { lookOf } from "../kit/sprites"
import { EMPTY } from "../kit/types"

const focus = { picked: null, armed: null, person: null }

// the columns where a carried mug changes the frame, against the same frame without it
function mugColumns(face: Actor["face"], moving: boolean) {
  const draw = (mug: number) => {
    const sc = new Scene(48, 48, 4)
    const seat = { agent: "hronir", thread_id: 1, title: "", warm: false, thinking: false, doing: null, archetype: "builder" }
    const spot = { x: 24, y: 40, aisle: 44, pose: "stand" as const, face, kind: "roam" as const }
    drawActors(sc, [{ seat, look: lookOf("hronir"), x: 24, y: 40, path: moving ? [{ x: 30, y: 40 }] : [], spot, spotKey: "", pose: "stand", face, moving, until: 0, emote: null, emoteUntil: 0, leaving: false, doingSince: 0, stretch: 0, snack: 0, finished: -1000, five: 0, mug, cooled: 0, warmth: 0 }], new Map(), EMPTY, focus)
    return sc.finish().rgba
  }
  const [with_, without] = [draw(9999), draw(0)]
  const cols = new Set<number>()
  for (let i = 0; i < with_.length; i += 4) if (with_[i] !== without[i] || with_[i + 1] !== without[i + 1] || with_[i + 2] !== without[i + 2]) cols.add((i / 4) % 48)
  return [...cols]
}

describe("a coffee carried", () => {
  // it was drawn a pixel off their left side whatever way they faced: walking right, it trailed
  // behind them like a ghost
  test("is in the hand on the side they walk toward, not trailing behind", () => {
    const right = mugColumns("right", true), left = mugColumns("left", true)
    expect(right.length).toBeGreaterThan(0)
    expect(Math.min(...right)).toBeGreaterThanOrEqual(24)
    expect(Math.max(...left)).toBeLessThan(24)
  })

  test("stays within the figure's twelve columns", () => {
    for (const face of ["down", "up", "left", "right"] as const) {
      const cols = mugColumns(face, false)
      expect(cols.length).toBeGreaterThan(0)
      expect(Math.min(...cols)).toBeGreaterThanOrEqual(18)
      expect(Math.max(...cols)).toBeLessThanOrEqual(29)
    }
  })
})
