import { describe, expect, test } from "bun:test"
import { Canvas } from "../kit/canvas"
import { CATALOGUE, type Home, type HomeTile } from "../kit/home"
import { ANNEX_PAD, SPRITES, TILE, TILE_ART, annexHeight, paintAnnex, paintTile, renderHome, rotated } from "../kit/homeart"
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

describe("annex", () => {
  const one = { tiles: [{ kind: "garden", at: [3, 5] }] } as Home
  test("no tiles → no height, nothing painted", () => {
    expect(annexHeight({ tiles: [] })).toBe(0)
    const c = new Canvas(40, 40), before = Buffer.from(c.rgba).toString("hex")
    paintAnnex(c, { tiles: [] }, 0)
    expect(Buffer.from(c.rgba).toString("hex")).toBe(before)
  })
  test("height covers the tile rows; a tile paints where paintTile would", () => {
    expect(annexHeight(one)).toBe(14 + 2 * ANNEX_PAD)
    const c = new Canvas(60, annexHeight(one))
    paintAnnex(c, one, 0)
    const ref = new Canvas(TILE, TILE)
    paintTile(ref, 0, 0, one.tiles[0]!)
    const at = (cv: Canvas, x: number, y: number) => Buffer.from(cv.rgba).readUInt32LE((y * cv.width + x) * 4)
    expect(at(c, ANNEX_PAD + 1 + 5, ANNEX_PAD + 1 + 5)).toBe(at(ref, 5, 5))
  })
})
