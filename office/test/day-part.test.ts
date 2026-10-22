import { describe, expect, test } from "bun:test"
import { baseLook, wearerOf, wearing } from "../kit/looks"
import type { DataPart } from "../kit/parts"

const part: DataPart = { id: "gen:2026-10-22", day: "2026-10-22", slot: "head", front: { 2: "..yyyyyy...." }, side: { 2: "..yyyyyy...." }, back: { 2: "..yyyyyy...." } }
const bench = ["yu", "lonnrot", "tzinacan", "hronir"]

describe("the day's wearer", () => {
  test("one of the bench, the same whatever order they are listed in", () => {
    const w = wearerOf("2026-10-22", bench)
    expect(bench).toContain(w!)
    expect(wearerOf("2026-10-22", [...bench].reverse())).toBe(w)
  })
  test("it rotates: over a month more than one actor wears", () => {
    const days = Array.from({ length: 30 }, (_, i) => `2026-10-${String(i + 1).padStart(2, "0")}`)
    expect(new Set(days.map((d) => wearerOf(d, bench))).size).toBeGreaterThan(1)
  })
  test("nobody about, nobody wears", () => expect(wearerOf("2026-10-22", [])).toBeUndefined())
  test("wearing puts the part in its slot over what was there, and leaves the base look alone", () => {
    const base = { ...baseLook("yu"), parts: { head: { id: "tophat" }, hand: { id: "mug" } } }
    const on = wearing(base, part)
    expect(on.parts).toEqual({ head: { id: part.id }, hand: { id: "mug" } })
    expect(base.parts!.head).toEqual({ id: "tophat" })
  })
})
