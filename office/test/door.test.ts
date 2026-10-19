import { describe, expect, test } from "bun:test"
import { arrivals, pickVisitor, RING_FIRST, seasonal } from "../kit/door"
import { EMPTY, type Agents } from "../kit/types"

const snap = (sha: string | null, ok = true): Agents => ({ ...EMPTY, ok, release: sha ? { sha, cut_at: "2026-10-12T00:00:00Z" } : null })
const need = (level: "blocking" | "decide") => ({ level })

describe("who comes by", () => {
  test("seasonal visitors keep their days", () => {
    expect(seasonal(new Date(2026, 9, 31))).toBe("trick")
    expect(seasonal(new Date(2026, 11, 20))).toBe("carol")
    expect(seasonal(new Date(2026, 9, 12))).toBeNull()
  })
  test("the holiday windows' edges: Dec 18-24 carols, Oct 31 only trick-or-treat; Feb 14 and Dec 31 bring no visitor of their own", () => {
    expect(seasonal(new Date(2026, 11, 17))).toBeNull()
    expect(seasonal(new Date(2026, 11, 18))).toBe("carol")
    expect(seasonal(new Date(2026, 11, 24))).toBe("carol")
    expect(seasonal(new Date(2026, 11, 25))).toBeNull()
    expect(seasonal(new Date(2026, 9, 30))).toBeNull()
    expect(seasonal(new Date(2026, 1, 14))).toBeNull()
    expect(seasonal(new Date(2026, 11, 31))).toBeNull()
  })
  test("pickVisitor is a pure function of the roll and the day; pizza is never scheduled", () => {
    const day = new Date(2026, 9, 12)
    const kinds = new Set([0, 0.2, 0.4, 0.6, 0.8, 0.999].map((r) => pickVisitor(r, day)))
    expect(kinds).toEqual(new Set(["carrier", "cookies", "tourist"]))
    expect(pickVisitor(0.1, new Date(2026, 9, 31))).toBe("trick")
  })
  test("the first ring is far enough out to leave seeded tests alone", () => expect(RING_FIRST).toBeGreaterThan(2_100))
})

describe("what the snapshots say arrived", () => {
  test("a changed sha is a cut: pizza", () => expect(arrivals(snap("a"), snap("b"), [], [])).toEqual(["pizza"]))
  test("the same sha, or a first look, is nothing", () => {
    expect(arrivals(snap("a"), snap("a"), [], [])).toEqual([])
    expect(arrivals(snap("a", false), snap("b"), [], [])).toEqual([])
  })
  test("no release to one: a first cut counts", () => expect(arrivals(snap(null), snap("a"), [], [])).toEqual(["pizza"]))
  test("more letters in the box is the carrier; fewer, or the same, is not", () => {
    expect(arrivals(snap("a"), snap("a"), [need("decide")], [need("decide"), need("blocking")])).toEqual(["carrier"])
    expect(arrivals(snap("a"), snap("a"), [need("decide"), need("decide")], [need("decide")])).toEqual([])
  })
})
