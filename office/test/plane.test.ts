import { describe, expect, test } from "bun:test"
import { FOLD, FRAMES, TEAR, UNFOLD, caughtNth, drawPlane, freshPosts, handoffFrom, launch, stepPlane, type Plane } from "../kit/plane"
import { Scene } from "../kit/draw"

const run = (p: Plane | null, max = 500) => {
  const seen: Plane[] = []
  while (p && seen.length < max) {
    seen.push(p)
    p = stepPlane(p)
  }
  return seen
}

describe("the paper aeroplane", () => {
  test("tears, folds, glides along its legs, unfolds, then is gone", () => {
    const s = run(launch({ x: 0, y: 0 }, [], { x: 30, y: 0 }))
    expect(s[0]!.phase).toBe("tear")
    expect(s.filter((p) => p.phase === "tear").length).toBe(TEAR)
    expect(s.filter((p) => p.phase === "fold").length).toBe(FOLD)
    expect(s.filter((p) => p.phase === "unfold").length).toBe(UNFOLD)
    const last = s.filter((p) => p.phase === "glide").at(-1)!
    expect(last.at).toEqual({ x: 30, y: 0 })
  })
  test("a hand-off passes over the old lead on the way: one flight, two legs", () => {
    const via = { x: 10, y: 40 }
    const s = run(launch({ x: 0, y: 0 }, [via], { x: 60, y: 0 }))
    expect(s.some((p) => p.phase === "glide" && p.at.x === 10 && p.at.y === 40)).toBe(true)
    expect(run(launch({ x: 0, y: 0 }, [], { x: 60, y: 0 })).length).toBeLessThan(s.length)
  })
  test("a leg with a hold stays put that many ticks (Argos has it)", () => {
    const held = run(launch({ x: 0, y: 0 }, [{ x: 12, y: 0, hold: 20 }], { x: 30, y: 0 }))
    const free = run(launch({ x: 0, y: 0 }, [{ x: 12, y: 0 }], { x: 30, y: 0 }))
    expect(held.length - free.length).toBe(20)
  })
  test("Argos catches every 4th plane, deterministically", () => {
    expect([0, 1, 2, 3, 4, 7].map(caughtNth)).toEqual([false, false, false, true, false, true])
  })
})

describe("freshPosts", () => {
  const row = (at: string, who: string | null, kind = "message", thread_id: number | null = 7) => ({ kind, at, thread_id, who, text: "x" })
  test("only uqbar's messages, only unseen, oldest first; the first load plays nothing", () => {
    const feed = [row("3", "uqbar"), row("2", "andrew"), row("1", "uqbar"), row("0", "uqbar", "fact")]
    const seen = new Set<string>()
    expect(freshPosts(feed, seen, true)).toEqual([])
    expect(freshPosts(feed, seen, false)).toEqual([])
    expect(freshPosts([row("4", "uqbar"), ...feed], seen, false).map((x) => x.at)).toEqual(["4"])
    expect(freshPosts([row("4", "uqbar"), ...feed], seen, false)).toEqual([])
  })
  test("a post with no thread has nowhere to fly", () => {
    expect(freshPosts([row("9", "uqbar", "message", null)], new Set(), false)).toEqual([])
  })
})

describe("drawing the plane", () => {
  test("every frame is rectangular, 6-8 wide, two-colour paint only", () => {
    expect(Object.keys(FRAMES).sort()).toEqual(["folded", "plane", "planeUp", "sheet", "unfold"])
    for (const [name, rows] of Object.entries(FRAMES)) {
      expect(rows.length, name).toBeLessThanOrEqual(8)
      for (const r of rows) {
        expect(r.length, name).toBe(rows[0]!.length)
        expect(r.length, name).toBeGreaterThanOrEqual(6)
        expect(r.length, name).toBeLessThanOrEqual(8)
        expect(r, name).toMatch(/^[.pk]+$/)
      }
    }
  })
  test("drawPlane queues one overhead draw per plane in every phase", () => {
    for (const phase of ["tear", "fold", "glide", "unfold"] as const) {
      const sc = new Scene(64, 48, 0)
      const before = sc.overhead.length
      drawPlane(sc, { phase, t: 2, at: { x: 5, y: 5 }, legs: [], hold: 0 })
      expect(sc.overhead.length - before, phase).toBe(1)
    }
  })
})

describe("handoffFrom", () => {
  const NOW = Date.parse("2026-10-10T03:00:00Z")
  const visit = (from: string, to: string, secs: number) => ({ from, to, workspace_id: 1, at: new Date(NOW - secs * 1000).toISOString() })
  const a = (live: boolean) => ({
    uqbar: live ? { agent: "uqbar", thread_id: 1, title: "", warm: false } : null,
    threads: [{ id: 7, lead: "w1" }],
  })
  test("the freshest staffing hand-off to the post's lead, within a minute: the old lead's name", () => {
    const vs = [visit("a", "w1", 50), visit("b", "w1", 10), visit("c", "w9", 5)]
    expect(handoffFrom(vs, a(true), 7, NOW)).toBe("b")
  })
  test("none when stale, when it was not to this lead, or when no uqbar session is live", () => {
    expect(handoffFrom([visit("a", "w1", 90)], a(true), 7, NOW)).toBeNull()
    expect(handoffFrom([visit("a", "w2", 5)], a(true), 7, NOW)).toBeNull()
    expect(handoffFrom([visit("a", "w1", 5)], a(false), 7, NOW)).toBeNull()
  })
})
