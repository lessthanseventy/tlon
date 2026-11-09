import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { doing, pickErrand, REST, UQBAR, type Errand, type ErrandKind } from "../kit/volume"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office, seeded } from "./golden"

const NOW = new Date(2026, 9, 5, 15, 0)
/** the office with uqbar's session on its study (no card), mid-turn or idle */
const withBook = (thinking = false) => {
  const a = office(4)
  return viewOf({ ...a, roster: [...a.roster, { agent: "uqbar", thread_id: 999, title: "Uqbar's study", warm: true, thinking, workspace_id: 1 }] }, 1)
}
type Inner = {
  errand: Errand | null; bookSaid: { text: string } | null; fallen: boolean; flinch: number; erratumUntil: number; tick: number
  errandFor(a: unknown, k: ErrandKind): Errand; noticed(actor: unknown, what: string): void; actors: Map<string, unknown>
}
const room = () => { const r = new WideRoom(696); return { r, i: r as unknown as Inner } }
const run = (r: WideRoom, a: ReturnType<typeof withBook>, n: number) => { for (let k = 0; k < n; k++) r.step(a) }

describe("pickErrand", () => {
  const all = { dark: true, working: true, cat: true, dog: true, hire: true }
  test("never the last one; a nap only after dark; nobody to read over, no shoulder; no pets, no pets", () => {
    for (let r = 0; r < 1; r += 0.01) {
      expect(pickErrand(r, "cork", all)).not.toBe("cork")
      expect(pickErrand(r, null, { ...all, dark: false })).not.toBe("nap")
      expect(pickErrand(r, null, { ...all, working: false })).not.toBe("shoulder")
      expect(["nina", "argos", "hat"]).not.toContain(pickErrand(r, null, { ...all, cat: false, dog: false }))
      expect(pickErrand(r, null, { ...all, hire: false })).not.toBe("hire")
    }
  })
  test("every pastime has its lines, and its tip says what it is up to", () => {
    for (const k of ["shoulder", "cork", "shelf", "mirror", "nap", "nina", "argos", "window", "tv", "clock", "lap", "erratum", "hall", "hire", "hat"] as const) {
      expect(UQBAR[k].length).toBeGreaterThan(0)
      expect(doing({ kind: k, path: [], dwell: 0, arrived: null })).toBeTruthy()
    }
  })
})

describe("the book's day", () => {
  test("no session: it sleeps on the shelf and says nothing", () => seeded(3, () => {
    const { r, i } = room(), a = viewOf(office(4), 1)
    run(r, a, 3000)
    expect(i.errand).toBeNull(); expect(i.bookSaid).toBeNull()
  }))
  test("a session waking says hello; idle, it goes off on errands and comes back between them", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 2)
    expect(UQBAR.wake).toContain(i.bookSaid?.text as never)
    const seen = new Set<ErrandKind>()
    for (let k = 0; k < 12000; k++) { r.step(a); if (i.errand?.arrived != null) seen.add(i.errand.kind) }
    expect(seen.size).toBeGreaterThanOrEqual(3)
  }))
  test("mid-turn it stays on its work: no errands", () => seeded(3, () => {
    const { r, i } = room(), a = withBook(true)
    for (let k = 0; k < REST.min * 4; k++) { r.step(a); expect(i.errand).toBeNull() }
  }))
  test("it tidies the shelf itself: the spine it knocked flat stands again", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 5)
    expect(i.fallen).toBe(true)
    i.errand = i.errandFor(a, "shelf")
    run(r, a, 400)
    expect(i.fallen).toBe(false)
  }))
  test("the mirror: it snaps shut and says why", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 80) // the hello has had its say
    i.errand = i.errandFor(a, "mirror")
    let shut = false
    for (let k = 0; k < 400 && !shut; k++) { r.step(a); shut = i.flinch > i.tick }
    expect(shut).toBe(true)
    expect(UQBAR.mirror).toContain(i.bookSaid?.text as never)
  }))
  test("a landing: a lap of honour, ribbon in the shipped colour, and its line", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 80)
    i.noticed([...i.actors.values()][0], "shipped")
    expect(i.errand?.kind).toBe("lap")
    expect(UQBAR.lap).toContain(i.bookSaid?.text as never)
    const fr = r.render(a, focus, measure, NOW)
    expect(fr.hits.find((h) => h.tip?.startsWith("Uqbar"))?.tip).toContain("shipped")
  }))
  test("something new stuck: an erratum, the ribbon goes red", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 80)
    r.step({ ...a, triage: { stalled: 1 } })
    expect(i.erratumUntil).toBeGreaterThan(i.tick)
    expect(UQBAR.erratum).toContain(i.bookSaid?.text as never)
    expect(r.render(a, focus, measure, NOW).hits.find((h) => h.tip?.startsWith("Uqbar"))?.tip).toContain("failing")
  }))
  test("the hallway and the hat: it flies to each and says its line; the hat is for Argos", () => seeded(3, () => {
    for (const kind of ["hall", "hat"] as const) {
      const { r, i } = room(), a = withBook()
      run(r, a, 80)
      i.errand = i.errandFor(a, kind)
      for (let k = 0; k < 800 && i.errand?.arrived == null; k++) r.step(a)
      expect(UQBAR[kind]).toContain(i.bookSaid?.text as never)
    }
  }))
  test("a new hire: the book goes to look them over, once, and says their name", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 80)
    const hire = { workspace_id: 1, seat_id: 99, agent_id: 99, name: "w9", archetype: "builder", lead: false, model: null, ask: null }
    const raw = office(4)
    const more = viewOf({ ...raw, bench: [...raw.bench, hire], roster: [...raw.roster, { agent: "uqbar", thread_id: 999, title: "Uqbar's study", warm: true, thinking: false, workspace_id: 1 }, { agent: "w9", thread_id: 998, title: "t9", warm: false, thinking: false, workspace_id: 1 }] }, 1)
    run(r, more, 5)
    i.errand = i.errandFor(more, "hire")
    expect(i.errand.name).toBe("w9")
    for (let k = 0; k < 800 && i.errand?.arrived == null; k++) r.step(more)
    expect(i.bookSaid?.text).toContain("w9")
    expect(r.render(more, focus, measure, NOW).hits.find((h) => h.tip?.startsWith("Uqbar"))?.tip).toContain("w9")
  }))
  test("reading over a shoulder: it hovers over someone mid-turn, open, and the tip names them", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 300)
    i.errand = i.errandFor(a, "shoulder")
    for (let k = 0; k < 600 && i.errand?.arrived == null; k++) r.step(a)
    const tip = r.render(a, focus, measure, NOW).hits.find((h) => h.tip?.startsWith("Uqbar"))?.tip ?? ""
    expect(tip).toMatch(/reading over \S+'s shoulder/)
  }))
})

describe("Argos's hat", () => {
  const hats = (r: WideRoom) => {
    const blits: string[][] = []
    const sc = { f: 0, tick: 0, hits: [], balloons: [], item: (_y: number, fn: () => void) => fn(), px: () => {}, text: () => {}, figure: () => {}, blit: (rows: string[]) => { blits.push(rows) } }
    ;(r as unknown as { drawDog(sc: unknown): void }).drawDog(sc)
    return blits.filter((rows) => rows.some((row) => row.includes("g")))
  }
  test("he wears it from the errand's arrival for a while, and not before or after", () => seeded(3, () => {
    const { r, i } = room(), a = withBook()
    run(r, a, 80)
    expect(hats(r)).toHaveLength(0)
    i.errand = i.errandFor(a, "hat")
    for (let k = 0; k < 800 && i.errand?.arrived == null; k++) r.step(a)
    expect(hats(r)).toHaveLength(1)
    run(r, a, 500)
    expect(hats(r)).toHaveLength(0)
  }))
})
