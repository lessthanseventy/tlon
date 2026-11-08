import { describe, expect, test } from "bun:test"
import { NONE, SECRETS, TROPHIES, bump, findSecret, newlyWon, night, parse, rows, serialize, won } from "../kit/trophies"

const at = (iso: string) => new Date(`${iso}:00`)

describe("trophies", () => {
  test("nothing is won at the start; each trophy is won at exactly its goal", () => {
    expect(won(NONE)).toEqual([])
    const drill = bump(NONE, "drills")
    expect(won(drill).map((t) => t.id)).toEqual(["drill"])
    expect(won(bump(NONE, "treats", 99))).toEqual([])
    expect(won(bump(NONE, "treats", 100)).map((t) => t.id)).toEqual(["treats"])
    expect(won(bump(NONE, "balloons", 1000)).map((t) => t.id)).toEqual(["balloons"])
    expect(won(bump(NONE, "planes", 10)).map((t) => t.id)).toEqual(["planes"])
  })
  test("newlyWon names only the trophy a bump crossed", () => {
    const a = bump(NONE, "planes", 9)
    expect(newlyWon(a, bump(a, "planes")).map((t) => t.id)).toEqual(["planes"])
    expect(newlyWon(bump(a, "planes"), bump(a, "planes", 2))).toEqual([])
  })
  test("a week of green nights: consecutive evenings, a red one or a missed day starts over", () => {
    let t = NONE
    for (let d = 1; d <= 6; d++) t = night(t, at(`2026-03-0${d}T21:00`), false)
    expect(t.greenRun).toBe(6)
    expect(night(t, at("2026-03-06T22:00"), false)).toBe(t)
    expect(night(t, at("2026-03-07T10:00"), false)).toBe(t)
    expect(won(night(t, at("2026-03-07T21:00"), false)).map((x) => x.id)).toEqual(["green"])
    expect(night(t, at("2026-03-06T23:00"), true).greenRun).toBe(0)
    expect(night(t, at("2026-03-08T21:00"), false).greenRun).toBe(1)
  })
  test("the file round-trips and garbage is a fresh tally", () => {
    const t = findSecret(bump(NONE, "treats", 7), "konami")
    expect(parse(serialize(t))).toEqual(t)
    expect(parse("{nope")).toEqual(NONE)
    expect(parse('{"treats":-3,"secrets":["x","clock"]}')).toEqual({ ...NONE, secrets: ["clock"] })
  })
  test("secrets count once and only the known ones", () => {
    const t = findSecret(findSecret(NONE, "babel"), "babel")
    expect(t.secrets).toEqual(["babel"])
    expect(findSecret(t, "nope")).toBe(t)
  })
  test("the card has a row per trophy and the secrets row says n/3", () => {
    const r = rows(findSecret(bump(NONE, "drills"), "konami"))
    expect(r.length).toBe(TROPHIES.length + 1)
    expect(r[0]).toEqual({ won: true, name: "first fire drill", note: "won" })
    expect(r.at(-1)).toEqual({ won: false, name: "secrets", note: `1/${SECRETS.length}` })
  })
})
