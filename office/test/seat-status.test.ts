import { describe, expect, test } from "bun:test"
import { Glob } from "bun"
import { crewOf, STATUS_ORDER, statusGlyph, statusTone, statusWord, type SeatStatus } from "../kit/crew"
import { CREW_GROUPS } from "../tui/order"
import { EMPTY, type Agents, type Seat } from "../kit/types"

const seat = (agent: string, over: Partial<Seat> = {}): Seat => ({ agent, thread_id: 0, title: "", warm: false, workspace_id: 1, ...over })
const office = (roster: Seat[], bench: string[] = []): Agents => ({
  ...EMPTY, ok: true, roster,
  bench: bench.map((name, i) => ({ workspace_id: 1, seat_id: i + 1, agent_id: i + 1, name, archetype: "builder", lead: false, model: null, ask: null })),
})

describe("one seat status, one renderer", () => {
  test("glyph, word and tone per state", () => {
    expect(STATUS_ORDER.map(statusGlyph)).toEqual(["!", "●", "○", "◌", "·"])
    expect(STATUS_ORDER.map(statusWord)).toEqual(["waiting on you", "working", "idle", "cold", "off"])
    expect(new Set(STATUS_ORDER.map(statusGlyph)).size).toBe(5)
    expect(STATUS_ORDER.every((s) => statusTone(s))).toBe(true)
  })

  test("the server's word on the roster is the crew's status; no roster row at all is off", () => {
    const a = office([seat("ireneo", { status: "cold" }), seat("emma", { status: "working", thinking: false })], ["ireneo", "emma", "nolan"])
    expect(Object.fromEntries(crewOf(a).map((c) => [c.name, c.status]))).toEqual({ ireneo: "cold", emma: "working", nolan: "off" })
  })

  test("a person with several sessions shows their most urgent one", () => {
    const a = office([seat("ireneo", { status: "idle", thread_id: 1 }), seat("ireneo", { status: "waiting", thread_id: 2 })], ["ireneo"])
    expect(crewOf(a).find((c) => c.name === "ireneo")!.status).toBe("waiting")
  })

  test("an older server (no status anywhere) gets the same words worked out from warmth", () => {
    const a = office([seat("ireneo", { thinking: true }), seat("emma", { warm: true })], ["ireneo", "emma", "nolan"])
    expect(Object.fromEntries(crewOf(a).map((c) => [c.name, c.status]))).toEqual({ ireneo: "working", emma: "idle", nolan: "cold" })
  })

  test("the crew screen groups by the same words", () => {
    const g = CREW_GROUPS.find((x) => x.name === "status")!
    const labels = (["working", "cold", "off"] as SeatStatus[]).map((s) => g.label({ name: "x", archetype: null, manager: false, lead: false, status: s, thread: null, title: "" }))
    expect(labels).toEqual(["working", "cold", "off"])
    expect(g.rank!("cold")).toBeGreaterThan(g.rank!("idle"))
  })

  // art that is not a seat's state: the pet-temperament slider (kit/pets.ts), a schedule's enabled
  // mark and a health check's tick (tui/main.ts)
  test("● ○ ◌ are a seat's state in kit/crew.ts only, bar the three non-seat uses", async () => {
    const hits: string[] = []
    for (const dir of ["kit", "tui", "rooms"]) for await (const f of new Glob(`${dir}/**/*.ts`).scan({ cwd: `${import.meta.dir}/..` })) {
      const lines = (await Bun.file(`${import.meta.dir}/../${f}`).text()).split("\n")
      lines.forEach((l, i) => { if (/[●○◌]/.test(l) && f !== "kit/crew.ts") hits.push(`${f}:${i + 1}`) })
    }
    expect(hits.map((h) => h.split(":")[0]!).sort()).toEqual(["kit/pets.ts", "tui/main.ts", "tui/main.ts"])
  })
})
