import { describe, expect, test } from "bun:test"
import { PNG } from "pngjs"
import { snapSheet } from "../cli"
import { lookOf, paints } from "../kit/sprites"

function solidPng(w: number, h: number, hex: string): Buffer {
  const png = new PNG({ width: w, height: h })
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
  for (let i = 0; i < w * h; i++) { png.data[i * 4] = r!; png.data[i * 4 + 1] = g!; png.data[i * 4 + 2] = b!; png.data[i * 4 + 3] = 255 }
  return PNG.sync.write(png)
}

describe("import-sprite round trip", () => {
  test("a 12x22 solid-colour PNG snaps to one char, repeated", () => {
    const paint = paints("#fff", lookOf("hronir"))
    const buf = solidPng(12, 22, paint.k!) // fieldInk — the darkest, least ambiguous role
    const rows = snapSheet(buf, 12, 22, paint)
    expect(rows).toHaveLength(22)
    expect(new Set(rows.map((r) => new Set(r).size === 1 ? [...r][0] : "?"))).toEqual(new Set(["k"]))
  })
  test("refuses a size that isn't 12x22 or 48x22", () => {
    expect(() => snapSheet(solidPng(10, 10, "#000000"), 10, 10, paints("#fff", lookOf("hronir")))).toThrow(/12x22|48x22/)
  })
})
