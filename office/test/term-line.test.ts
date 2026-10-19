import { expect, test } from "bun:test"
import { cells, line } from "../tui/term"

const plain = (s: string) => s.replace(/\x1b\[[\d;]*m/g, "")

test("text that fits is padded to the width, untouched", () => {
  expect(plain(line([{ s: "abc" }], 6))).toBe("abc   ")
})

test("text that does not fit ends in an ellipsis, in whatever the width, across segments and wide characters", () => {
  expect(plain(line([{ s: "the arcade has many cabinets" }], 12))).toBe("the arcade …")
  expect(plain(line([{ s: "ab" }, { s: "cdefgh" }], 5))).toBe("abcd…")
  const wide = plain(line([{ s: "日本語日本語" }], 7))
  expect(cells(wide)).toBe(7)
  expect(wide.endsWith("…")).toBe(true)
})

test("text exactly the width is not cut", () => {
  expect(plain(line([{ s: "abcdef" }], 6))).toBe("abcdef")
})
