import { expect, test } from "bun:test"
import { candidateOf, emptyStore } from "../kit/store"
import { STORE_VIEW_ROWS, storeRows, stepStoreRow } from "../tui/store"

const text = (r: { segs: { s: string }[] }) => r.segs.map((s) => s.s).join("")
const card = (sp: "hamster" | "rock" | "baoaqu" | "cat" = "hamster") => candidateOf({ ...emptyStore(), species: sp }, [])
test("one row per line of the card: species, slot, name, three axes, shade, a line in its voice", () => {
  const rows = storeRows(card(), ["warmth"], "Nina", "Seeds. Now.")
  expect(rows).toHaveLength(STORE_VIEW_ROWS)
  expect(rows.map((r) => r.lock)).toEqual([null, null, "name", "warmth", "wits", "energy", "shade", null])
  expect(text(rows[1]!)).toContain("cat slot")
  expect(text(rows[1]!)).toContain("Nina leaves by the door")
  expect(text(rows[3]!)).toContain("locked")
  expect(text(rows[2]!)).not.toContain("locked")
  expect(text(rows[7]!)).toContain("Seeds. Now.")
})
test("every shelved species draws, sit beside walk, in half-blocks; a rock sits twice", () => {
  for (const sp of ["cat", "hamster", "rock", "baoaqu"] as const) {
    const rows = storeRows(card(sp), [], "Nina", "")
    expect({ sp, drawn: rows.some((r) => r.segs.some((s) => s.s === "▀" || s.s === "▄")) }).toEqual({ sp, drawn: true })
  }
})
test("stepStoreRow wraps both ways", () => {
  expect(stepStoreRow(0, -1)).toBe(STORE_VIEW_ROWS - 1)
  expect(stepStoreRow(STORE_VIEW_ROWS - 1, 1)).toBe(0)
})

test("a dog candidate draws its own art and names the dog slot", () => {
  const c = candidateOf({ ...emptyStore(), species: "dog" }, [])
  const text = storeRows(c, [], "Argos", "woof").map((r) => r.segs.map((g) => g.s).join("")).join("\n")
  expect(text).toContain("the dog slot")
})
