import { describe, expect, test } from "bun:test"
import { Canvas } from "../kit/canvas"
import { CATALOGUE, OFFICE_ROWS, cellPx, floorHeight, type Home, type HomeTile } from "../kit/home"
import { mailbox } from "../kit/mailbox"
import { SPRITES, TILE, TILE_ART, paintFloor, paintTile, renderHome, rotated } from "../kit/homeart"
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
  const onBig = (weather?: string) => { const c = new Canvas(TILE + 8, TILE + 8); paintTile(c, 4, 4, garden, weather); return c }
  const inside = (i: number) => { const p = i >> 2, x = p % (TILE + 8), y = Math.floor(p / (TILE + 8)); return x >= 4 && x < 4 + TILE && y >= 4 && y < 4 + TILE }
  test("rain and snow stay inside the tile", () => {
    for (const k of ["rain", "snow"]) {
      const c = onBig(k)
      c.rgba.forEach((v, i) => { if (!inside(i)) expect(v).toBe(0) })
    }
  })
  test("snow is pale, not the fence's amber", () => {
    const dry = onBig(), c = onBig("snow")
    let changed = 0
    for (let i = 0; i < c.rgba.length; i += 4) {
      if (c.rgba[i] === dry.rgba[i] && c.rgba[i + 1] === dry.rgba[i + 1] && c.rgba[i + 2] === dry.rgba[i + 2]) continue
      changed++
      expect(c.rgba[i + 2]).toBeGreaterThan(150)
    }
    expect(changed).toBeGreaterThan(0)
  })
  test("renderHome paints the weather it is given", () => {
    const g = { home: { tiles: [garden] } as never, cursor: [0, 0] as [number, number], carrying: null, refused: false, w: 60, h: 40 }
    expect(Buffer.from(renderHome({ ...g, weather: "rain" }).rgba).equals(Buffer.from(renderHome(g).rgba))).toBe(false)
  })
})

describe("floor", () => {
  const one = { tiles: [{ kind: "garden" as const, at: [0, OFFICE_ROWS] as [number, number] }] }
  test("no tiles → nothing painted", () => {
    const c = new Canvas(60, 60), before = Buffer.from(c.rgba)
    paintFloor(c, { tiles: [] })
    expect(Buffer.from(c.rgba).equals(before)).toBe(true)
  })
  test("a tile paints where paintTile would, at its absolute cell, with no pad", () => {
    const h = floorHeight(one), c = new Canvas(60, h), ref = new Canvas(60, h)
    paintFloor(c, one)
    const [x, y] = cellPx([0, OFFICE_ROWS])
    paintTile(ref, x, y, one.tiles[0]!)
    for (let j = 0; j < TILE; j++) for (let i = 0; i < TILE; i++) {
      const k = ((y + j) * 60 + x + i) * 4
      expect([...c.rgba.slice(k, k + 4)]).toEqual([...ref.rgba.slice(k, k + 4)])
    }
  })
})

describe("the mailbox on the street tile", () => {
  const street: HomeTile = { kind: "street", at: [0, 0] }
  const dec = { level: "decide" as const }, blk = { level: "blocking" as const }
  const mail = (needs: { level: "blocking" | "decide" }[] | undefined, t: HomeTile = street) => {
    const c = new Canvas(TILE + 8, TILE + 8); paintTile(c, 4, 4, t, null, needs && mailbox(needs)); return c
  }
  const hex = (c: Canvas) => Buffer.from(c.rgba).toString("hex")
  test("letters change the street; an empty box is still a box", () => {
    expect(hex(mail([dec]))).not.toBe(hex(mail([])))
    expect(hex(mail([]))).not.toBe(hex(mail(undefined)))
  })
  test("a blocking need raises the flag", () => {
    expect(hex(mail([blk]))).not.toBe(hex(mail([dec])))
  })
  test("only the street has a mailbox", () => {
    for (const kind of CATALOGUE.filter((k) => k !== "street")) {
      const t: HomeTile = { kind, at: [0, 0] }
      expect(hex(mail([blk], t))).toBe(hex(mail(undefined, t)))
    }
  })
  test("it stays inside the tile", () => {
    mail([blk, dec]).rgba.forEach((v, i) => {
      const p = i >> 2, x = p % (TILE + 8), y = Math.floor(p / (TILE + 8))
      if (x < 4 || x >= 4 + TILE || y < 4 || y >= 4 + TILE) expect(v).toBe(0)
    })
  })
  test("renderHome carries it through", () => {
    const home = { tiles: [street] }
    const f = (m?: ReturnType<typeof mailbox>) => Buffer.from(renderHome({ home, cursor: [0, 0], carrying: null, refused: false, w: 60, h: 60, mail: m }).rgba).toString("hex")
    expect(f(mailbox([blk]))).not.toBe(f())
  })
})

describe("streak frames on the living tile", () => {
  const living = { tiles: [{ kind: "living", at: [0, 0] }] } as never
  const view = (frames?: { routine: number; tier: number }[]) => Buffer.from(renderHome({ ...base, home: living, frames }).rgba).toString("hex")
  test("one frame hung changes the living tile's pixels", () => expect(view([{ routine: 1, tier: 1 }])).not.toBe(view()))
  test("no frames is the plain living tile", () => expect(view([])).toBe(view()))
  test("the tile fits three frames: a fourth is not drawn", () =>
    expect(view([{ routine: 1, tier: 1 }, { routine: 2, tier: 1 }, { routine: 3, tier: 1 }, { routine: 4, tier: 1 }]))
      .toBe(view([{ routine: 1, tier: 1 }, { routine: 2, tier: 1 }, { routine: 3, tier: 1 }])))
  test("a higher tier draws a thicker frame, so the tier reads without colour", () =>
    expect(view([{ routine: 1, tier: 2 }])).not.toBe(view([{ routine: 1, tier: 1 }])))
  test("frames hang on the living tile only", () => {
    const street = { tiles: [{ kind: "street", at: [0, 0] }] } as never
    const f = (fr: { routine: number; tier: number }[]) => Buffer.from(renderHome({ ...base, home: street, frames: fr }).rgba).toString("hex")
    expect(f([{ routine: 1, tier: 1 }])).toBe(f([]))
  })
})

describe("the bed on the bedroom tile", () => {
  const bedroom = { tiles: [{ kind: "bedroom", at: [0, 0] }] } as never
  const view = (bed?: "asleep" | "cat" | null, h: unknown = bedroom) => Buffer.from(renderHome({ ...base, home: h as never, bed }).rgba).toString("hex")
  test("asleep changes the bedroom's pixels", () => expect(view("asleep")).not.toBe(view()))
  test("the cat on the bed looks different from you asleep, so it reads without colour", () => expect(view("cat")).not.toBe(view("asleep")))
  test("an empty bed is the plain bedroom", () => expect(view(null)).toBe(view()))
  test("only the bedroom has a bed", () => {
    const street = { tiles: [{ kind: "street", at: [0, 0] }] }
    expect(view("asleep", street)).toBe(view(undefined, street))
  })
})

describe("the office in the build grid", () => {
  test("a view with `top` paints the office's cells apart from an empty cell below them", () => {
    const view = { home: { tiles: [{ kind: "street", at: [0, OFFICE_ROWS] }] } as Home, cursor: [0, OFFICE_ROWS] as [number, number], carrying: null, refused: false, w: 120, h: 80 }
    const plain = renderHome(view), dimmed = renderHome({ ...view, top: OFFICE_ROWS })
    expect(Buffer.from(dimmed.rgba).equals(Buffer.from(plain.rgba))).toBe(false)
  })
})
