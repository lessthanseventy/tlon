import { describe, expect, test } from "bun:test"
import { boardColumns, viewOf, type BoardCtx } from "../kit/crew"
import { entryOf, type EntryEvent, type EntryNeed } from "../kit/entry"
import { EMPTY, type Agents, type Seat, type Thread } from "../kit/types"

// a workspace with work spread across the board: two at build, three at review (two waiting on
// you), one doing, plus a ticket — and a second coworker so the pivot has two rows
const NOW = new Date("2026-10-10T13:00:00Z")
const iso = (h: number) => new Date(Date.UTC(2026, 9, 10, h, 0)).toISOString()
const seat = (agent: string, tid: number, thinking = false): Seat => ({ agent, thread_id: tid, title: `t${tid}`, warm: true, thinking, workspace_id: 1 })
const th = (id: number, lead: string, stage: string | null, opts: Partial<Thread> = {}): Thread => ({ id, title: `thread ${id}`, stage, awaiting: null, workspace_id: 1, lead, seat: "desk", ...opts })

function world(): Agents {
  const a: Agents = {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "surveyor", meta: true, read_only: true, model: "" }, { name: "builder", meta: false, read_only: false, model: "" }],
    bench: [
      { workspace_id: 1, seat_id: 1, agent_id: 2, name: "nolan", archetype: "builder", lead: true, model: null, ask: null },
      { workspace_id: 1, seat_id: 2, agent_id: 3, name: "paula", archetype: "builder", lead: false, model: null, ask: null },
    ],
    threads: [
      th(11, "nolan", "build"),
      th(12, "nolan", "build"),
      th(13, "nolan", "review", { awaiting: "qa" }),
      th(14, "paula", "review", { prompt: { summary: "pick a flavour", options: null } }),
      th(15, "paula", "review"),
      th(16, "paula", null), // DOING: a plain thread someone is at a desk on
    ],
    roster: [
      seat("nolan", 11, true), seat("nolan", 12), seat("nolan", 13),
      seat("paula", 14, true), seat("paula", 15), seat("paula", 16),
    ],
    tickets: [{ id: 50, workspace_id: 1, project_id: null, title: "a ticket", priority: "med" }],
    triage: { "1": 2 },
    health: { state: "warn", problems: ["the disk is full"], checks: { running: null, waiting: [] }, merge_queue: [] },
  }
  return a
}

const ctx: BoardCtx = { maxLeaves: null, needs: [], checking: null, merging: [] }
const needs: EntryNeed[] = [
  { kind: "gate", level: "blocking", thread_id: 13, title: "qa on #13", at: iso(10) },
  { kind: "ask", level: "decide", thread_id: 14, title: "pick a flavour", at: iso(11) },
]
const feed: EntryEvent[] = [
  { kind: "work_landed", at: iso(9), thread_id: 12, who: "tlon", text: "#12 landed" },
  { kind: "work_landed", at: iso(8), thread_id: 11, who: "tlon", text: "#11 landed" },
  { kind: "message", at: iso(12), thread_id: 14, who: "uqbar", text: "asked paula to pick" },
  { kind: "message", at: iso(6), thread_id: 99, who: "uqbar", text: "cut a release" }, // not on the board
]

describe("the entry (U)", () => {
  const a = world(), v = viewOf(a, 1)
  const e = entryOf(v, ctx, needs, feed, NOW)

  test("counts match the board, column for column", () => {
    const board = Object.fromEntries(boardColumns(v, ctx).map((c) => [c.name, c.items.length]))
    expect(e.counts).toEqual(board)
    expect(e.counts.BUILD).toBe(2)
    expect(e.counts.REVIEW).toBe(3)
    expect(e.counts.DOING).toBe(1)
    expect(e.counts.TICKETS).toBe(1)
  })

  test("a footnote key opens its thread — each thread waiting on you is a footnote", () => {
    const opening = e.footnotes.filter((f) => f.act.kind === "thread")
    // #13 (awaiting qa) and #14 (a prompt) both need you
    expect(opening.map((f) => (f.act as { tid: number }).tid).sort((x, y) => x - y)).toEqual([13, 14])
  })

  test("the pivot is stage × coworker, counts per cell, and its column totals match the board", () => {
    expect(e.pivot.stages).toEqual(["DOING", "SPEC", "PLAN", "BUILD", "REVIEW"])
    const byName = Object.fromEntries(e.pivot.rows.map((r) => [r.cow, r]))
    expect(byName.nolan.cells).toHaveLength(5) // DOING SPEC PLAN BUILD REVIEW
    // nolan: build×2, review×1; paula: doing×1, review×2
    const build = e.pivot.stages.indexOf("BUILD"), review = e.pivot.stages.indexOf("REVIEW"), doing = e.pivot.stages.indexOf("DOING")
    expect(byName.nolan.cells[build]!.count).toBe(2)
    expect(byName.nolan.cells[review]!.count).toBe(1)
    expect(byName.paula.cells[doing]!.count).toBe(1)
    expect(byName.paula.cells[review]!.count).toBe(2)
    // the pivot's stage totals (excluding TICKETS, which has no owner) match the board's stage columns
    for (const st of e.pivot.stages) {
      const inPivot = e.pivot.rows.reduce((n, r) => n + r.cells[e.pivot.stages.indexOf(st)]!.count, 0)
      expect(inPivot).toBe(e.counts[st])
    }
  })

  test("shipped today and Uqbar's diary come from today's events", () => {
    const shipped = e.sections.find((s) => s.label.startsWith("SHIPPED"))!
    expect(shipped.lines.map((l) => l.text)).toEqual(["#12 landed", "#11 landed"])
    // uqbar's diary: today's acts by uqbar, newest first; each opens its thread
    expect(e.diary.map((d) => d.text)).toEqual(["asked paula to pick", "cut a release"])
    const open14 = e.diary.find((d) => d.text.startsWith("asked"))!
    expect(open14.act).toEqual({ kind: "thread", tid: 14 })
  })

  test("known problems: owned go to the beacon, unowned to the rack", () => {
    const known = e.footnotes.find((f) => f.act.kind === "beacon")
    const unowned = e.footnotes.find((f) => f.act.kind === "rack")
    expect(known).toBeDefined() // triage has 2 stuck
    expect(unowned).toBeDefined() // health has a problem
  })
})