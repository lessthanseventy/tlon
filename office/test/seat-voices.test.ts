import { describe, expect, test } from "bun:test"
import { SEAT_VOICE, seatLine, SEATS } from "../kit/seat-voices"

describe("the §2 voice table", () => {
  test("every sandbox seat has a voice", () => {
    // the sandbox bench (tui/sandbox.ts NAMES), minus scharlach who has his own
    for (const name of ["tertius", "hronir", "lonnrot", "yu", "beatriz", "nolan", "emma", "ireneo", "daneri", "sonny"])
      expect(SEAT_VOICE[name]).toBeDefined()
  })
  test("each voice has at least three banter lines, none empty", () => {
    for (const name of SEATS) {
      const lines = SEAT_VOICE[name]!.banter
      expect(lines.length).toBeGreaterThanOrEqual(3)
      for (const l of lines) expect(l.trim().length).toBeGreaterThan(0)
    }
  })
})

describe("Scharlach's voice", () => {
  test("crisp and slightly too formal — the §2 Dwight", () => {
    const lines = SEAT_VOICE["scharlach"]!.banter
    expect(lines.length).toBeGreaterThanOrEqual(3)
    // over-formal: every line reads as a report or a noted duty, not a quip
    for (const l of lines) expect(l).toMatch(/[A-Z]/) // starts a sentence
    expect(lines.some((l) => /noted|resolved|filed|recorded|logged|issue|duly|hereby/i.test(l))).toBe(true)
  })
})

describe("seatLine", () => {
  test("returns one of the seat's own lines, {name} filled in", () => {
    const l = seatLine("sonny", [])
    expect(SEAT_VOICE["sonny"]!.banter.map((x) => x.replaceAll("{name}", "you")).includes(l)).toBe(true)
  })
  test("skips what was said lately while anything else is unsaid", () => {
    const all = SEAT_VOICE["tertius"]!.banter.map((x) => x.replaceAll("{name}", "you"))
    const said = all.slice(0, all.length - 1)
    expect(seatLine("tertius", said)).toBe(all[all.length - 1])
  })
  test("a seat with no canned voice falls back to the generic builder voice, never an error", () => {
    const l = seatLine("nobody", [])
    expect(typeof l).toBe("string")
    expect(l.length).toBeGreaterThan(0)
  })
})