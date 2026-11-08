import { expect, test } from "bun:test"
import { RELEASE_MIN, releaseText, tickerText, Tv } from "../kit/tv"

test("every channel runs, lights the screen, and stays on it", () => {
  const tv = new Tv(48, 28), seen = new Set<string>()
  tv.setTicker({ sha: null, queue: 0, phone: 0, last: null })
  for (let c = 0; c < 13; c++) {
    tv.next()
    let lit = 0
    for (let i = 0; i < 250; i++) { tv.step(); lit = Math.max(lit, tv.screen.dots.filter((d) => d > 0).length) }
    expect({ channel: tv.channel, lit: lit > 5, hues: tv.screen.dots.every((d) => d <= 5) }).toEqual({ channel: tv.channel, lit: true, hues: true })
    seen.add(tv.channel)
  }
  expect(seen.size).toBe(13)
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

test("the ticker's text is the release, the queue, the phone and the newest landing, ASCII only", () => {
  expect(tickerText({ sha: "650fa4a1234", queue: 2, phone: 3, last: "fix the door" })).toBe("release 650fa4a  *  merge queue 2  *  phone 3  *  last landing: fix the door")
  expect(tickerText({ sha: null, queue: 0, phone: 0, last: null })).toBe("no release yet  *  merge queue 0  *  phone 0  *  nothing landed yet")
  expect(tickerText({ sha: "abc1234", queue: 0, phone: 0, last: "naïve — dash" })).toContain("na?ve ? dash")
})

test("the ticker channel crawls the numbers it is handed and follows them when they change", () => {
  const tv = new Tv(48, 28)
  tv.setTicker({ sha: null, queue: 0, phone: 0, last: null })
  while (tv.channel !== "ticker") tv.next()
  const crawl = () => { const frames: string[] = []; for (let i = 0; i < 400; i++) { tv.step(); frames.push(tv.screen.dots.join("")) } return frames }
  const a = crawl()
  expect(new Set(a).size).toBeGreaterThan(50)
  expect(tv.screen.dots.every((d) => d <= 5)).toBe(true)
  tv.setTicker({ sha: "abc1234", queue: 9, phone: 4, last: "something landed" })
  const b = crawl()
  expect(b.join()).not.toBe(a.join())
})

test("until the room hands it numbers the ticker is not in the rotation", () => {
  const tv = new Tv(48, 28), seen = new Set<string>()
  for (let c = 0; c < 30; c++) { tv.next(); seen.add(tv.channel) }
  expect(seen.size).toBe(12)
  expect(seen.has("ticker")).toBe(false)
})
