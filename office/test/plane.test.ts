import { describe, expect, test } from "bun:test"
import { FOLD, TEAR, UNFOLD, caughtNth, freshPosts, launch, stepPlane, type Plane } from "../kit/plane"

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
