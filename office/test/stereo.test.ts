import { describe, expect, test } from "bun:test"
import { marqueeWindow, parseNowPlaying } from "../kit/stereo"

describe("parseNowPlaying", () => {
  test("title and artist, no bpm field", () => {
    expect(parseNowPlaying("Song|Artist|")).toEqual({ text: "Song - Artist", bpm: null })
  })
  test("title only, blank artist", () => {
    expect(parseNowPlaying("Song||")).toEqual({ text: "Song", bpm: null })
  })
  test("bpm field present and numeric", () => {
    expect(parseNowPlaying("Song|Artist|128")).toEqual({ text: "Song - Artist", bpm: 128 })
  })
  test("bpm field present but not a number", () => {
    expect(parseNowPlaying("Song|Artist|unknown")).toEqual({ text: "Song - Artist", bpm: null })
  })
  test("no title and no artist: no player playing", () => {
    expect(parseNowPlaying("||")).toBeNull()
    expect(parseNowPlaying("")).toBeNull()
  })
})

describe("marqueeWindow", () => {
  test("text shorter than the window is padded, not scrolled", () => {
    expect(marqueeWindow("hi", 10, 0)).toBe("hi".padEnd(10))
    expect(marqueeWindow("hi", 10, 37)).toBe("hi".padEnd(10))
  })
  test("text longer than the window scrolls as tick advances", () => {
    const text = "a very long now-playing string indeed"
    const a = marqueeWindow(text, 10, 0), b = marqueeWindow(text, 10, 5)
    expect(a.length).toBe(10)
    expect(b.length).toBe(10)
    expect(a).not.toBe(b)
  })
  test("the window wraps around (loops) rather than stopping", () => {
    const text = "loop me"
    const windows = new Set<string>()
    for (let tick = 0; tick < 200; tick++) windows.add(marqueeWindow(text, 6, tick))
    // a short cycle: the same handful of windows repeat, it never grows unbounded
    expect(windows.size).toBeLessThan(20)
  })
})
