import { expect, test } from "bun:test"
import { Tv } from "../kit/tv"

test("every channel runs, lights the screen, and stays on it", () => {
  const tv = new Tv(48, 28), seen = new Set<string>()
  for (let c = 0; c < 12; c++) {
    tv.next()
    let lit = 0
    for (let i = 0; i < 250; i++) { tv.step(); lit = Math.max(lit, tv.screen.dots.filter((d) => d > 0).length) }
    expect({ channel: tv.channel, lit: lit > 5, hues: tv.screen.dots.every((d) => d <= 5) }).toEqual({ channel: tv.channel, lit: true, hues: true })
    seen.add(tv.channel)
  }
  expect(seen.size).toBe(12)
})

test("showLevel paints the level on the screen, then hands back to the interrupted show", () => {
  const tv = new Tv(48, 28), before = tv.channel
  tv.showLevel(7, 10)
  expect(tv.channel).toBe("level")
  tv.step()
  expect(tv.screen.dots.filter((d) => d > 0).length).toBeGreaterThan(20)
  for (let i = 0; i < 10; i++) tv.step()
  expect(tv.channel).toBe(before)
})
