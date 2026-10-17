import { describe, expect, test } from "bun:test"
import { affinities, relation } from "../kit/company"

const bench = ["scharlach", "tertius", "lonnrot", "nolan", "daneri"]

describe("affinities", () => {
  test("the three verbs, names matched against the bench", () => {
    const people = "admires tertius (won't admit it), needles Lönnrot who reviews his fixes, would cover for nolan."
    expect(affinities(people, bench)).toEqual({ admires: ["tertius"], needles: ["lonnrot"], covers: ["nolan"] })
  })
  test("accents and case fold; a name off the bench is ignored", () => {
    expect(affinities("Needles LÖNNROT and Beatriz", bench).needles).toEqual(["lonnrot"])
  })
  test("no People section, or no verbs → nothing", () => {
    expect(affinities("", bench)).toEqual({ admires: [], needles: [], covers: [] })
    expect(affinities("gets along with everyone", bench)).toEqual({ admires: [], needles: [], covers: [] })
  })
  test("each clause is its own: the verb applies up to the next verb or period", () => {
    expect(affinities("admires daneri; needles nolan.", bench)).toEqual({ admires: ["daneri"], needles: ["nolan"], covers: [] })
  })
})

const soulOf = (people: string) => ({ sections: { People: people }, raw: "" })
const souls = { scharlach: soulOf("admires tertius, needles lonnrot"), lonnrot: soulOf(""), tertius: soulOf(""), daneri: soulOf("needles tertius and admires tertius") }

describe("relation", () => {
  test("friend, rival, none — symmetric", () => {
    expect(relation("scharlach", "tertius", souls, bench)).toBe("friend")
    expect(relation("tertius", "scharlach", souls, bench)).toBe("friend")
    expect(relation("scharlach", "lonnrot", souls, bench)).toBe("rival")
    expect(relation("lonnrot", "scharlach", souls, bench)).toBe("rival")
    expect(relation("nolan", "scharlach", souls, bench)).toBe("none")
  })
  test("admires wins over needles; a seat with no soul is none with everyone", () => {
    expect(relation("daneri", "tertius", souls, bench)).toBe("friend")
    expect(relation("nolan", "daneri", souls, bench)).toBe("none")
  })
  test("a handle with a capital or an accent still matches its own folded affinities", () => {
    const caps = ["Scharlach", "Tertius", "Lönnrot"], s = { Scharlach: soulOf("admires tertius, needles lonnrot") }
    expect(relation("Scharlach", "Tertius", s, caps)).toBe("friend")
    expect(relation("Tertius", "Scharlach", s, caps)).toBe("friend")
    expect(relation("Lönnrot", "Scharlach", s, caps)).toBe("rival")
  })
})
