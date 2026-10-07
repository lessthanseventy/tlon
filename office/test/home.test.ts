import { describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  canPlace, connected, drop, move, pickUp, place, remove, rotate, startBuild, undo, type Home, type HomeTile,
} from "../kit/home"
import { loadHome, saveHome } from "../tui/home"

const byAt = (x: HomeTile, y: HomeTile) => x.at[0] - y.at[0] || x.at[1] - y.at[1]

describe("connected", () => {
  test("a single tile, or none, is one piece", () => {
    expect(connected([])).toBe(true)
    expect(connected([{ kind: "living", at: [0, 0] }])).toBe(true)
  })
  test("two tiles sharing an edge are one piece; a gap between them is two", () => {
    expect(connected([{ kind: "living", at: [0, 0] }, { kind: "kitchen", at: [1, 0] }])).toBe(true)
    expect(connected([{ kind: "living", at: [0, 0] }, { kind: "kitchen", at: [2, 0] }])).toBe(false)
  })
})

describe("canPlace", () => {
  const home: Home = { tiles: [{ kind: "living", at: [0, 0] }, { kind: "kitchen", at: [1, 0] }] }
  test("refuses an occupied cell", () => {
    expect(canPlace(home, { kind: "bathroom", at: [0, 0] })).toBe(false)
  })
  test("allows a cell that keeps the floor in one piece", () => {
    expect(canPlace(home, { kind: "bathroom", at: [1, 1] })).toBe(true)
  })
  test("refuses a cell that would strand the rest of the floor off on its own", () => {
    // living(0,0) - kitchen(1,0) - bedroom(2,0): a tile at (1,1) off the middle splits nothing,
    // but replacing the middle tile's only link would. Build a floor where the new tile is an
    // island with no shared edge to anything already down.
    const bridge: Home = { tiles: [{ kind: "living", at: [0, 0] }, { kind: "kitchen", at: [1, 0] }] }
    expect(canPlace(bridge, { kind: "bedroom", at: [5, 5] })).toBe(false)
  })
})

describe("build mode: place, pick up, drop, rotate, remove, undo", () => {
  test("a driven session builds a 2x2 home", () => {
    let b = startBuild({ tiles: [] })
    b = place(b) // living, 1st in the catalogue, at (0,0)
    b = move(b, 1, 0)
    b = place(b); b = place(b) // two presses: living, then kitchen, at (1,0)
    b = move(b, 0, 1)
    b = place(b); b = place(b); b = place(b) // living, kitchen, bathroom, at (1,1)
    b = move(b, -1, 0)
    b = place(b); b = place(b); b = place(b); b = place(b) // …bedroom, at (0,1)
    const want: HomeTile[] = [
      { kind: "living", at: [0, 0] }, { kind: "bedroom", at: [0, 1] },
      { kind: "kitchen", at: [1, 0] }, { kind: "bathroom", at: [1, 1] },
    ]
    expect(b.home.tiles.slice().sort(byAt)).toEqual(want.slice().sort(byAt))
  })
  test("n cycles the catalogue on a cell that already has a tile", () => {
    let b = startBuild({ tiles: [] })
    b = place(b)
    expect(b.home.tiles[0]!.kind).toBe("living")
    b = place(b)
    expect(b.home.tiles[0]!.kind).toBe("kitchen")
  })
  test("pick up, carry, and drop moves a tile", () => {
    let b = startBuild({ tiles: [{ kind: "living", at: [0, 0] }] })
    b = pickUp(b)
    expect(b.carrying?.kind).toBe("living")
    expect(b.home.tiles).toEqual([])
    expect(b.writes).toBe(0) // carrying is in memory only — nothing to write yet
    b = move(b, 2, 0)
    b = drop(b)
    expect(b.carrying).toBeNull()
    expect(b.home.tiles).toEqual([{ kind: "living", at: [2, 0] }])
    expect(b.writes).toBe(1)
  })
  test("a drop that cuts the floor in two is refused, and never counts as a write", () => {
    let b = startBuild({ tiles: [
      { kind: "living", at: [0, 0] }, { kind: "kitchen", at: [1, 0] }, { kind: "bathroom", at: [2, 0] },
    ] })
    b = move(b, 1, 0) // onto the kitchen, the middle tile
    b = pickUp(b)
    b = move(b, 0, 5) // far away — placing it there leaves living and bathroom disconnected
    const before = b.home
    b = drop(b)
    expect(b.refused).toBe(true)
    expect(b.carrying?.kind).toBe("kitchen") // still carried — the drop never happened
    expect(b.home).toBe(before)
    expect(b.writes).toBe(0) // so there is nothing a caller should persist: the file stays as it was
  })
  test("remove takes a tile off the floor; rotate marks it; undo steps back", () => {
    let b = startBuild({ tiles: [{ kind: "living", at: [0, 0] }] })
    b = rotate(b)
    expect(b.home.tiles[0]!.rot).toBe(90)
    b = remove(b)
    expect(b.home.tiles).toEqual([])
    b = undo(b)
    expect(b.home.tiles[0]!.kind).toBe("living")
  })
  test("undo only remembers the last ten writes", () => {
    let b = startBuild({ tiles: [] })
    for (let i = 0; i < 15; i++) { b = move(b, 1, 0); b = place(b); b = move(b, -1, -1) }
    expect(b.history.length).toBe(10)
  })
})

describe("home.json round trip", () => {
  test("a built home saves and loads back the same", () => {
    const dir = mkdtempSync(join(tmpdir(), "tlon-home-"))
    const path = join(dir, "home.json")
    try {
      const home: Home = { tiles: [{ kind: "living", at: [0, 0] }, { kind: "kitchen", at: [1, 0] }] }
      saveHome(home, path)
      expect(loadHome(path)).toEqual(home)
    } finally { rmSync(dir, { recursive: true, force: true }) }
  })
  test("a missing file is an empty home, not a throw", () => {
    expect(loadHome(join(tmpdir(), "tlon-home-missing", "home.json"))).toEqual({ tiles: [] })
  })
})
