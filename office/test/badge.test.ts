import { expect, test } from "bun:test"
import { badge, line, type Seg } from "../tui/term"

const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "")
const mark: Seg = { s: "  ✎ pencils down ", fg: "#000000", bg: "#ffaa00", bold: true }

test("a highlighted mark keeps its gap plain, so it never touches the segment before it", () => {
  const out = line([{ s: "  ⇄ day crew" }, ...badge(mark)], 60)
  expect(strip(out)).toContain("day crew  ✎ pencils down")
  const bgAt = out.indexOf("\x1b[48;")
  expect(strip(out.slice(0, bgAt))).toMatch(/day crew {2}$/)
})

test("a mark with no leading gap is left alone", () => {
  expect(badge({ s: "x", bg: "#000000" })).toHaveLength(1)
})
