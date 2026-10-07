import { describe, expect, test } from "bun:test"
import type { Frame } from "../kit/canvas"
import { geometry, hitAt, textLayer } from "../tui/paint"
import { tokenize } from "../tui/term"

const frame = (w: number, h: number, over: Partial<Frame> = {}): Frame => ({ rgba: new Uint8Array(w * h * 4).fill(255), width: w, height: h, ink: [], hits: [], ...over })
const strip = (s: string) => s.replace(/\x1b\[[\d;]*m/g, "")

describe("tokenize", () => {
  test("keys, mouse, and the replies to our queries", () => {
    const { inputs, rest } = tokenize("q\x1b[A\r\x1b[<0;10;5M\x1b[<35;11;5M\x1b[6;18;9t\x1b_Gi=31;OK\x1b\\\x1b[?62;22c\x1b")
    expect(rest).toBe("")
    expect(inputs).toEqual([
      { t: "key", key: "q" }, { t: "key", key: "up" }, { t: "key", key: "enter" },
      { t: "mouse", button: 0, col: 10, row: 5, press: true, motion: false },
      { t: "mouse", button: 3, col: 11, row: 5, press: true, motion: true },
      { t: "cell", h: 18, w: 9 }, { t: "graphics", ok: true }, { t: "da" }, { t: "key", key: "esc" },
    ])
  })
  test("a sequence split across reads waits for its end", () => {
    const a = tokenize("x\x1b[<0;1")
    expect(a.inputs).toEqual([{ t: "key", key: "x" }])
    expect(tokenize(a.rest + ";2M").inputs[0]).toMatchObject({ t: "mouse", col: 1, row: 2 })
  })
})

describe("paint", () => {
  test("kitty geometry: whole-pixel scale that fits, centred, at most 5×", () => {
    const g = geometry(144, 190, 100, 80, 17, { w: 10, h: 20 }, true)
    // 1000px across / 144 → 6 and (80 - 17) rows × 20px / 190 → 6, capped at 5: 720 × 950px
    expect([g.k, g.cols, g.rows, g.col]).toEqual([5, 72, 48, 14])
    expect(geometry(144, 190, 40, 80, 17, { w: 10, h: 20 }, true).k).toBe(2)
  })
  test("half blocks: text lands on the cell under its logical position; clicks map back", () => {
    const g = { k: 2, cw: 4, ch: 8, col: 3, row: 1, cols: 10, rows: 5, kitty: false, floorW: 20, floorH: 20 }
    const fr = frame(20, 20, {
      ink: [{ t: "text", s: "hi", x: 10, y: 9, color: "#ffffff", size: 12, align: "center" }],
      hits: [{ x: 8, y: 8, w: 4, h: 4, tip: "spot", act: { kind: "crew" } }],
    })
    const rows = textLayer(fr, g).map(strip)
    // x 10 → px 20 → col 5, centred "hi" starts at col 4; y 9 → px 18 → row 2
    expect(rows[2]).toBe("▀▀▀▀hi▀▀▀▀")
    expect(rows[0]).toBe("▀".repeat(10))
    // terminal col 3+5+1, row 1+2+1 is cell (5,2) → logical (11, 10): inside the hit
    expect(hitAt(fr, g, 9, 4)?.tip).toBe("spot")
    expect(hitAt(fr, g, 4, 2)).toBeUndefined()
  })
  test("a label never overwrites one already on its cells", () => {
    const g = { k: 2, cw: 4, ch: 8, col: 0, row: 0, cols: 10, rows: 2, kitty: false, floorW: 20, floorH: 8 }
    const fr = frame(20, 8, { ink: [
      { t: "text", s: "lonnrot", x: 0, y: 4, color: "#ffffff", size: 11, align: "left" },
      { t: "text", s: "yu", x: 0, y: 4.5, color: "#ffffff", size: 11, align: "left" },
    ] })
    expect(strip(textLayer(fr, g)[0]!)).toBe("lonnrot▀▀▀")
  })
  test("half blocks carry two art pixels per cell", () => {
    const g = geometry(4, 4, 4, 20, 10, null, false)
    expect([g.cols, g.rows, g.kitty]).toEqual([4, 2, false])
    expect(strip(textLayer(frame(4, 4), g)[0]!)).toBe("▀▀▀▀")
  })
})
