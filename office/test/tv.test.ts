import { expect, test } from "bun:test"
import { RELEASE_MIN, releaseText, Tv } from "../kit/tv"

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

test("a cut's notes are typeset as an encyclopedia entry", () => {
  expect(releaseText("650fa4a1234", ["fix the door.", "  add\nthe TV "])).toBe("UQBAR — release 650fa4a. 1. fix the door. 2. add the TV.")
  expect(releaseText("650fa4a", [])).toBe("UQBAR — release 650fa4a.")
})

test("the release channel takes over from the show, crawls the entry, and ends once settled and read", () => {
  const tv = new Tv(48, 28), before = tv.channel
  tv.showRelease("650fa4a", ["fix the door", "add the TV channel"])
  expect(tv.channel).toBe("release")
  const frames: string[] = []
  for (let i = 0; i < 40; i++) { tv.step(); frames.push(tv.screen.dots.join("")) }
  expect(tv.screen.dots.filter((d) => d > 0).length).toBeGreaterThan(40)
  expect(new Set(frames).size).toBeGreaterThan(10)
  expect(tv.screen.dots.every((d) => d <= 5)).toBe(true)
  // not settled: it stays up however long
  for (let i = 0; i < RELEASE_MIN * 2; i++) tv.step()
  expect(tv.channel).toBe("release")
  tv.settle()
  tv.step()
  expect(tv.channel).toBe(before)
})

test("a settle before the minimum waits for it", () => {
  const tv = new Tv(48, 28), before = tv.channel
  tv.showRelease("650fa4a", ["x"])
  tv.settle()
  for (let i = 0; i < RELEASE_MIN - 2; i++) tv.step()
  expect(tv.channel).toBe("release")
  for (let i = 0; i < 4; i++) tv.step()
  expect(tv.channel).toBe(before)
})

test("a level flash wins over the release entry and hands back to it", () => {
  const tv = new Tv(48, 28)
  tv.showRelease("650fa4a", ["x"])
  tv.showLevel(3, 5)
  expect(tv.channel).toBe("level")
  for (let i = 0; i < 6; i++) tv.step()
  expect(tv.channel).toBe("release")
})
