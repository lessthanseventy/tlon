import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { CELL, HOME_BLOCKS, OFFICE_ROWS, cellPx } from "../kit/home"
import { floorPlan } from "../kit/floor"
import { DEFAULT_OFFICE } from "../kit/tiles"
import { office } from "./golden"

const blocksOf = (tiles?: Parameters<typeof floorPlan>[2], w = 696) => {
  const p = floorPlan(DEFAULT_OFFICE, w, tiles)
  return p.blocks(p.layout(viewOf(office(3), 1)))
}

describe("home tiles on the sim's floor", () => {
  test("a tile at [0, OFFICE_ROWS+1] adds its footprint at the cell's origin", () => {
    const base = blocksOf({ tiles: [] }), got = blocksOf({ tiles: [{ kind: "living", at: [0, OFFICE_ROWS + 1] }] })
    const [x, y] = cellPx([0, OFFICE_ROWS + 1])
    expect(got.length).toBe(base.length + HOME_BLOCKS.living.length)
    for (const b of HOME_BLOCKS.living) expect(got).toContainEqual({ x: x + b.x, y: y + b.y, w: b.w, h: b.h })
  })
  test("a tile two cells right is offset by 2*CELL in x", () => {
    const a = blocksOf({ tiles: [{ kind: "living", at: [0, OFFICE_ROWS + 1] }] }), b = blocksOf({ tiles: [{ kind: "living", at: [2, OFFICE_ROWS + 1] }] })
    const n = HOME_BLOCKS.living.length
    expect(b.slice(-n).map((r) => r.x - 2 * CELL)).toEqual(a.slice(-n).map((r) => r.x))
  })
  test("no home tiles → the plan is the office's, block for block", () => {
    expect(blocksOf({ tiles: [] })).toEqual(blocksOf(undefined))
  })
  test("local x=0 stays clear and every block sits inside its tile (the walking lane, unrotated)", () => {
    for (const rs of Object.values(HOME_BLOCKS)) for (const r of rs) {
      expect(r.x).toBeGreaterThanOrEqual(1)
      expect(r.x + r.w).toBeLessThanOrEqual(12)
      expect(r.y + r.h).toBeLessThanOrEqual(12)
    }
  })
  test("rotation turns a footprint with the sprite", () => {
    const rot = blocksOf({ tiles: [{ kind: "bedroom", at: [0, OFFICE_ROWS + 1], rot: 90 }] }).slice(-HOME_BLOCKS.bedroom.length)
    const [x, y] = cellPx([0, OFFICE_ROWS + 1]), b = HOME_BLOCKS.bedroom[0]!
    expect(rot[0]).toEqual({ x: x + (12 - b.y - b.h), y: y + b.x, w: b.h, h: b.w })
  })
})
