import { describe, expect, test } from "bun:test"
import { Canvas } from "../kit/canvas"
import { CATALOGUE, type HomeTile } from "../kit/home"
import { SPRITES, TILE, TILE_ART, paintTile, renderHome, rotated } from "../kit/homeart"
import { ROLE } from "../kit/palette"

describe("rotated", () => {
  const s = ["abc", "def", "ghi"]
  test("clockwise quarter turns", () => {
    expect(rotated(s, 0)).toEqual(s)
    expect(rotated(s, 90)).toEqual(["gda", "heb", "ifc"])
    expect(rotated(s, 180)).toEqual(["ihg", "fed", "cba"])
    expect(rotated(s, 270)).toEqual(["cfi", "beh", "adg"])
  })
})

const paint = (t: HomeTile) => { const c = new Canvas(TILE, TILE); paintTile(c, 0, 0, t); return Buffer.from(c.rgba).toString("hex") }

describe("sprites", () => {
  test("every catalogue kind has a TILE×TILE sprite", () => {
    for (const k of CATALOGUE) {
      expect(SPRITES[k]!.length).toBe(TILE)
      for (const row of SPRITES[k]!) expect(row.length).toBe(TILE)
    }
  })
  test("kinds look different from each other, and a rotated tile from its upright self", () => {
    const looks = CATALOGUE.map((kind) => paint({ kind, at: [0, 0] }))
    expect(new Set(looks).size).toBe(CATALOGUE.length)
    for (const kind of CATALOGUE) expect(paint({ kind, at: [0, 0], rot: 90 })).not.toBe(paint({ kind, at: [0, 0] }))
  })
  test("a kind with no art still draws (plain tile), and the hook takes over once registered", () => {
    const garden = { kind: "shed", at: [0, 0] } as unknown as HomeTile
    const plain = paint(garden)
    expect(plain).not.toBe(paint({ kind: "living", at: [0, 0] }))
    let called = 0
    TILE_ART.shed = (c, x, y) => { called++; c.px(x, y, TILE, TILE, "#112233") }
    try { expect(paint(garden)).not.toBe(plain); expect(called).toBe(1) } finally { delete TILE_ART.shed }
  })
})

const home = { tiles: [{ kind: "living", at: [0, 0] }, { kind: "street", at: [1, 0] }] } as const
const base = { home: home as never, cursor: [0, 0] as [number, number], carrying: null, refused: false, w: 200, h: 100 }

describe("renderHome", () => {
  test("a frame of the size asked, one bracket on the cursor", () => {
    const f = renderHome(base)
    expect([f.width, f.height, f.rgba.length]).toEqual([200, 100, 200 * 100 * 4])
    const b = f.ink.filter((i) => i.t === "brackets")
    expect(b.length).toBe(1)
    expect(b[0]).toMatchObject({ color: ROLE.attention })
  })
  test("a refused drop turns the cursor alarm-coloured", () => {
    expect(renderHome({ ...base, refused: true }).ink.find((i) => i.t === "brackets")).toMatchObject({ color: ROLE.alarm })
  })
  test("a carried tile shows at the cursor, dimmed against the same tile placed", () => {
    const empty = { tiles: [{ kind: "street", at: [1, 0] }] } as never
    const carrying = { kind: "living", at: [0, 0] } as never
    const hold = renderHome({ ...base, home: empty, carrying })
    const placed = renderHome({ ...base, home: { tiles: [carrying, { kind: "street", at: [1, 0] }] } as never })
    expect(Buffer.from(hold.rgba).equals(Buffer.from(placed.rgba))).toBe(false)
    expect(hold.rgba.some((v, i) => v !== 0 && i % 4 === 3)).toBe(true)
  })
})

describe("weather on the garden", () => {
  const garden: HomeTile = { kind: "garden", at: [0, 0] }
  const wet = (kind?: string | null) => { const c = new Canvas(TILE, TILE); paintTile(c, 0, 0, garden, kind); return Buffer.from(c.rgba).toString("hex") }
  test("rain, storm and snow each change the garden; clear, cloudy and unknown leave it as drawn", () => {
    const dry = wet()
    for (const k of ["clear", "partly", "cloudy", "fog", null, undefined]) expect(wet(k)).toBe(dry)
    expect(wet("rain")).not.toBe(dry)
    expect(wet("snow")).not.toBe(dry)
    expect(wet("rain")).not.toBe(wet("snow"))
    expect(wet("storm")).toBe(wet("rain"))
  })
  test("only the garden is out in it", () => {
    for (const kind of CATALOGUE.filter((k) => k !== "garden")) {
      const c = new Canvas(TILE, TILE); paintTile(c, 0, 0, { kind, at: [0, 0] }, "snow")
      expect(Buffer.from(c.rgba).toString("hex")).toBe(paint({ kind, at: [0, 0] }))
    }
  })
  test("snow piles on the fence: the fence row ends up lighter than it was", () => {
    const c = new Canvas(TILE, TILE); paintTile(c, 0, 0, garden, "snow")
    const d = new Canvas(TILE, TILE); paintTile(d, 0, 0, garden)
    const sum = (k: Canvas) => Array.from(k.rgba.slice(0, TILE * 4)).reduce((a, b) => a + b, 0)
    expect(sum(c)).toBeGreaterThan(sum(d))
  })
  test("renderHome paints the weather it is given", () => {
    const g = { home: { tiles: [garden] } as never, cursor: [0, 0] as [number, number], carrying: null, refused: false, w: 60, h: 40 }
    expect(Buffer.from(renderHome({ ...g, weather: "rain" }).rgba).equals(Buffer.from(renderHome(g).rgba))).toBe(false)
  })
})
