import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { CELL, HOME_BLOCKS, OFFICE_H, OFFICE_ROWS, cellPath, cellPx } from "../kit/home"
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

describe("the street", () => {
  const home = { tiles: [...Array.from({ length: 50 }, (_, i) => ({ kind: "street" as const, at: [i, OFFICE_ROWS] as [number, number] })), { kind: "living" as const, at: [1, OFFICE_ROWS + 1] as [number, number] }] }
  test("cellPath: BFS across a connected set of cells, start and end included", () => {
    expect(cellPath(home.tiles, [3, OFFICE_ROWS], [1, OFFICE_ROWS + 1])).toEqual([[3, OFFICE_ROWS], [2, OFFICE_ROWS], [1, OFFICE_ROWS], [1, OFFICE_ROWS + 1]])
    expect(cellPath(home.tiles, [0, 0], [1, OFFICE_ROWS + 1])).toEqual([])
  })
  test("the plan exposes the street's two doors", () => {
    const p = floorPlan(DEFAULT_OFFICE, 696, home)
    const [lx, ly] = cellPx([1, OFFICE_ROWS + 1])
    expect(p.doors!.office).toEqual({ x: 696 - 18, y: OFFICE_H + CELL / 2 })
    expect(p.doors!.home).toEqual({ x: lx, y: ly })
    expect(floorPlan(DEFAULT_OFFICE, 696).doors).toBeUndefined()
  })
  test("walk: office door → street → home door, and it hits no block", () => {
    const p = floorPlan(DEFAULT_OFFICE, 696, home), blocks = p.blocks(p.layout(viewOf(office(3), 1)))
    const pts = p.walk!(p.doors!.office, p.doors!.home)
    expect(pts[0]).toEqual(p.doors!.office)
    expect(pts.at(-1)).toEqual(p.doors!.home)
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1]!, b = pts[i]!
      for (let s = 0; s <= 20; s++) {
        const x = a.x + ((b.x - a.x) * s) / 20, y = a.y + ((b.y - a.y) * s) / 20
        expect(blocks.find((r) => x > r.x && x < r.x + r.w && y > r.y && y < r.y + r.h)).toBeUndefined()
      }
    }
  })
})
