import { expect, test } from "bun:test"
import { BODY, SMALL } from "../kit/font"

const ascii = Array.from({ length: 95 }, (_, i) => String.fromCharCode(32 + i))

test("each cut has its own glyph for every printable ASCII char, its spacing column blank", () => {
  for (const [name, cut] of Object.entries({ SMALL, BODY })) {
    const seen = new Map<string, string>()
    for (const ch of ascii) {
      const g = cut.glyph(ch), key = g.join(",")
      expect({ name, ch, rows: g.length, spacing: g.some((r) => r & 1), twin: seen.get(key) }).toEqual({ name, ch, rows: cut.h, spacing: false, twin: undefined })
      seen.set(key, ch)
    }
    expect(cut.glyph("é")).toEqual(cut.glyph("?"))
  }
})
