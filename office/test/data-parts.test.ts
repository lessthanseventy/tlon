import { afterEach, describe, expect, test } from "bun:test"
import { gearOf, idsIn, nextPart, useDataParts, type DataPart } from "../kit/parts"
import { lookOf, rollLook } from "../kit/sprites"

const part: DataPart = { id: "gen:2026-10-22", day: "2026-10-22", slot: "hand", front: { 11: "..........yy" }, side: { 11: ".yy........." }, back: { 11: "..........yy" } }
afterEach(() => useDataParts([]))

describe("data parts", () => {
  test("gearOf draws a gen: id from the loaded library, and nothing once it is gone", () => {
    expect(gearOf({ id: part.id })).toBeUndefined()
    useDataParts([part])
    expect(gearOf({ id: part.id })!.front[11]).toBe("..........yy")
  })
  test("they stay out of the roll: idsIn is code-only and every fixed name keeps its look", () => {
    const names = ["yu", "lonnrot", "tzinacan", "hronir", "uqbar", "daneri", "runeberg", "ulrikke"]
    const snap = () => JSON.stringify(names.map((n) => [lookOf(n), rollLook(n)]))
    const before = snap(), ids = idsIn("hand")
    useDataParts([part])
    expect(snap()).toBe(before)
    expect(idsIn("hand")).toEqual(ids)
  })
  test("nextPart offers them after the code parts of their slot, then none", () => {
    useDataParts([part])
    const codes = idsIn("hand"), seen: string[] = []
    let cur = nextPart("hand", undefined)
    for (let i = 0; i < 20 && cur; i++) { seen.push(cur.id); cur = nextPart("hand", cur) }
    expect(seen).toEqual([...codes, part.id])
  })
})
