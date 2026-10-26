import { expect, test } from "bun:test"
import { roll } from "../kit/hall"
import { SLOTS } from "../kit/parts"
import { hallRows, stepRow, HALL_ROWS } from "../tui/hall"

const VOCAB = { archetypes: ["builder", "reviewer"], grades: ["junior", "senior"], specialties: ["office", "server"] }
const cand = () => roll("hall:3", { taken: [], vocab: VOCAB })
const text = (r: { segs: { s: string }[] }) => r.segs.map(s => s.s).join("")

test("the card has one row per field then one per slot", () => {
  const rows = hallRows(cand(), {})
  expect(rows).toHaveLength(HALL_ROWS)
  expect(rows.map(r => r.lock)).toEqual([
    ...(["name", "archetype", "grade", "specialty"] as const).map(key => ({ kind: "fields" as const, key })),
    null, ...SLOTS.map(s => ({ kind: "slots" as const, key: s })), null,
  ])
})
test("rows say what they hold, and a locked one says so", () => {
  const c = cand()
  const rows = hallRows(c, { fields: ["grade"], slots: ["eyes"] })
  expect(text(rows[0]!)).toContain(c.name)
  expect(text(rows[2]!)).toContain(c.grade)
  expect(text(rows[2]!)).toContain("locked")
  expect(text(rows[1]!)).not.toContain("locked")
  expect(text(rows[4]!)).toContain(c.pitch)
  expect(text(rows[6]!)).toContain("locked")
})
test("the figure is drawn in three views beside the rows, half-height blocks", () => {
  const rows = hallRows(cand(), {})
  expect(rows[0]!.segs.some(s => s.s === "▀" || s.s === "▄")).toBe(true)
  expect(rows.every(r => r.segs.filter(s => s.bg !== undefined || s.fg !== undefined).length > 0)).toBe(true)
})
test("stepRow wraps both ways", () => {
  expect(stepRow(0, -1)).toBe(HALL_ROWS - 1)
  expect(stepRow(HALL_ROWS - 1, 1)).toBe(0)
  expect(stepRow(3, 1)).toBe(4)
})
test("the soul has a row of its own, last, that says what it holds and is not lockable", () => {
  const rows = hallRows(cand(), {})
  const last = rows[rows.length - 1]!
  expect(last.lock).toBeNull()
  expect(text(last)).toContain("soul")
  expect(text(hallRows({ ...cand(), soul: "## Wants\nsleep\n" }, {}).at(-1)!)).toContain("sleep")
})
