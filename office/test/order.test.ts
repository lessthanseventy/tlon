import { describe, expect, test } from "bun:test"
import type { Crew } from "../kit/crew"
import { arrange, CREW_GROUPS, CREW_SORTS, next } from "../tui/order"

const c = (name: string, o: Partial<Crew> = {}): Crew => ({ name, archetype: "builder", manager: false, lead: false, status: "idle", thread: null, title: "", ...o })
const crew = [
  c("zed", { status: "idle" }), c("amy", { status: "working", thread: 9, archetype: "reviewer" }),
  c("bo", { status: "waiting", thread: 3 }), c("cy", { status: "working", thread: 3, manager: true }),
]
const names = (xs: { items: Crew[] }[]) => xs.map((g) => g.items.map((x) => x.name))

describe("ordering a list", () => {
  test("next steps through the modes and wraps", () => {
    expect(next(["a", "b", "c"], "a")).toBe("b")
    expect(next(["a", "b", "c"], "c")).toBe("a")
  })
  test("no group, bench order is kept; a sort reorders", () => {
    expect(names(arrange(crew, CREW_SORTS[0]!.cmp, null))).toEqual([["zed", "amy", "bo", "cy"]])
    expect(names(arrange(crew, CREW_SORTS.find((s) => s.name === "name")!.cmp, null))).toEqual([["amy", "bo", "cy", "zed"]])
  })
  test("status sort puts waiting on you first, then working, then idle", () => {
    expect(names(arrange(crew, CREW_SORTS.find((s) => s.name === "status")!.cmp, null))[0]).toEqual(["bo", "amy", "cy", "zed"])
  })
  test("grouped by status: headed groups in rank order, the sort inside each", () => {
    const g = arrange(crew, CREW_SORTS.find((s) => s.name === "name")!.cmp, CREW_GROUPS.find((x) => x.name === "status")!)
    expect(g.map((x) => x.label)).toEqual(["waiting on you", "working", "idle"])
    expect(names(g)).toEqual([["bo"], ["amy", "cy"], ["zed"]])
  })
  test("grouped by thread: threads by id, the bench last", () => {
    const g = arrange(crew, CREW_SORTS[0]!.cmp, CREW_GROUPS.find((x) => x.name === "thread")!)
    expect(g.map((x) => x.label)).toEqual(["#3", "#9", "on the bench"])
  })
  test("grouped by role: managers apart", () => {
    const g = arrange(crew, CREW_SORTS[0]!.cmp, CREW_GROUPS.find((x) => x.name === "role")!)
    expect(g.map((x) => x.label).sort()).toEqual(["builder", "manager", "reviewer"])
  })
})
