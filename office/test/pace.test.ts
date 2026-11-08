import { expect, test } from "bun:test"
import { paced } from "../tui/pace"

/** fires a one-second timer for `seconds` of a fake clock and counts how often its body ran */
function firings(seconds: number, focused: () => boolean, idleMs: number) {
  let t = 0, runs = 0
  const tick = paced(focused, idleMs, () => { runs++ }, () => t)
  for (; t < seconds * 1000; t += 1000) tick()
  return runs
}

test("a timer runs every tick while focused", () => {
  expect(firings(5, () => true, 30_000)).toBe(5)
})

test("unfocused, a one-second timer fires only at the idle cadence", () => {
  expect(firings(5, () => false, 30_000)).toBe(0)
  expect(firings(90, () => false, 30_000)).toBe(2)
})

test("focus turned off for the middle of a run costs the timer only its idle ticks", () => {
  let t = 0, runs = 0, on = true
  const tick = paced(() => on, 30_000, () => { runs++ }, () => t)
  for (; t < 5000; t += 1000) tick()
  on = false
  for (; t < 10_000; t += 1000) tick()
  expect(runs).toBe(5)
  on = true
  tick()
  expect(runs).toBe(6)
})
