import { describe, expect, test } from "bun:test"
import { BOARD_LEGEND, boardColumns, cardState, epicChildren, groupRows, STATE_GLYPH, treeRows, stickyItems } from "../kit/crew"
import { EMPTY, type Agents, type Seat, type Thread, type Ticket } from "../kit/types"

const thread = (id: number, over: Partial<Thread> = {}): Thread => ({ id, title: `t${id}`, stage: "build", awaiting: null, workspace_id: 1, lead: "ireneo", seat: "idle", ...over })
const seat = (thread_id: number, over: Partial<Seat> = {}): Seat => ({ agent: "ireneo", thread_id, title: "", warm: false, workspace_id: 1, ...over })
const snap = (threads: Thread[], roster: Seat[] = []): Agents => ({ ...EMPTY, ok: true, threads, roster })
const col = (a: Agents, name: string) => boardColumns(a).find((c) => c.name === name)!.items.map((x) => (x.act.kind === "thread" ? x.act.tid : -1))

describe("a workline card's state", () => {
  test("running: its lead is at a desk — mid-turn says so", () => {
    const t = thread(7, { seat: "desk" })
    expect(cardState(snap([t]), t)).toEqual({ kind: "running", why: "ireneo is at a desk" })
    const busy = thread(7, { seat: "desk", thinking: ["ireneo"] })
    expect(cardState(snap([busy]), busy)?.why).toBe("ireneo is on it")
  })
  test("a warm session on the roster is not a desk: the server's seat is the one answer", () => {
    const t = thread(7)
    expect(cardState(snap([t], [seat(7, { warm: true })]), t)?.kind).toBe("idle")
  })
  test("parked: waiting for a seat under the leaf cap, with the count when the cap is known", () => {
    const t = thread(7, { seat: "parked" })
    const busy = [thread(1, { live: true }), thread(2, { live: true }), thread(3, { live: true, standing: true }), thread(4, { live: true, duty: true })]
    expect(cardState(snap([t, ...busy]), t, { maxLeaves: 2 })).toEqual({ kind: "parked", why: "waiting for a seat (2/2)", atCap: true })
    expect(cardState(snap([t]), t)).toEqual({ kind: "parked", why: "waiting for a seat", atCap: true })
  })
  test("idle: staffed, nobody at a desk and not waiting for one", () => {
    const t = thread(7)
    expect(cardState(snap([t]), t)).toEqual({ kind: "idle", why: "ireneo is not at a desk" })
  })
  test("needs you: it awaits the operator, asks something, or is on the needs list — before anything else", () => {
    expect(cardState(snap([]), thread(7, { awaiting: "spec approval" }))).toEqual({ kind: "needs", why: "awaits spec approval" })
    expect(cardState(snap([]), thread(7, { prompt: { id: 1, summary: "which one?" } }))?.why).toBe("asks: which one?")
    const t = thread(7, { seat: "desk" })
    expect(cardState(snap([t]), t, { needs: [7] })?.kind).toBe("needs")
  })
  test("the machine's queues show first: its full check running, or the merge queue landing it", () => {
    const t = thread(7, { seat: "desk" })
    expect(cardState(snap([t]), t, { checking: 7 })).toEqual({ kind: "checking", why: "its full check is running" })
    expect(cardState(snap([t]), t, { merging: [{ thread_id: 7, state: "landing" }] })?.why).toBe("landing now: gated on main")
    expect(cardState(snap([t]), t, { merging: [{ thread_id: 7, state: "queued" }] })?.kind).toBe("merging")
    expect(cardState(snap([t]), t, { checking: 8 })?.kind).toBe("running")
  })
  test("a verify workline stands in VERIFY, not BUILD; its check running or waiting says so", () => {
    const t = thread(7, { stage: "verify", seat: "desk" })
    expect(col(snap([t]), "VERIFY")).toEqual([7])
    expect(col(snap([t]), "BUILD")).toEqual([])
    expect(cardState(snap([t]), t, { checkWaiting: [7, 9] })).toEqual({ kind: "checking", why: "its full check waits its turn (2 waiting)" })
    expect(cardState(snap([t]), t, { checkWaiting: [9] })?.kind).toBe("running")
  })
  test("landed, its PR not merged yet (the server's `landing`): waiting on GitHub, on the REVIEW column — whoever leads it", () => {
    const t = thread(7, { stage: "merged", seat: "desk", landing: true })
    expect(cardState(snap([t]), t)).toEqual({ kind: "merging", why: "landing · merging on GitHub" })
    expect(cardState(snap([]), thread(7, { stage: "merged", lead: null, landing: true }))?.kind).toBe("merging")
    expect(col(snap([t]), "REVIEW")).toEqual([7])
  })
  test("merged and reopened (not landing): never drawn as waiting on GitHub, and off the board", () => {
    const t = thread(7, { stage: "merged", seat: "desk" })
    expect(cardState(snap([t]), t)?.kind).toBe("running")
    expect(boardColumns(snap([t])).flatMap((c) => c.items)).toEqual([])
  })
  test("nobody leads it: no state to claim", () => {
    expect(cardState(snap([]), thread(7, { lead: null }))).toBeNull()
  })
  test("the board's thread cards carry their state; tickets don't", () => {
    const t = thread(7, { seat: "desk" })
    const a = { ...snap([t]), tickets: [{ id: 3, workspace_id: 1, project_id: null, title: "x", priority: "normal" }] }
    const cols = boardColumns(a)
    expect(cols[0]!.items[0]!.state).toBeUndefined()
    expect(cols.find((c) => c.name === "BUILD")!.items[0]!.state?.kind).toBe("running")
  })
})

describe("who's doing what", () => {
  test("a plain thread someone is at a desk on is BUILD's, marked doing — not one parked or idle", () => {
    const a = snap([thread(1, { stage: null, seat: "desk" }), thread(2, { stage: null, seat: "parked" }), thread(3, { stage: null })])
    expect(col(a, "BUILD")).toEqual([1])
    expect(boardColumns(a).find((c) => c.name === "BUILD")!.items[0]!.stage).toBe("doing")
  })
  test("a standing duty is not work: off the stage columns", () => {
    const a = snap([thread(1, { stage: null, seat: "desk", duty: true }), thread(2, { stage: "build", seat: "desk", duty: true }), thread(3, { seat: "parked" })])
    expect(col(a, "BUILD")).toEqual([3])
  })
  test("a parked workline stays in its stage, marked parked", () => {
    const a = snap([thread(3, { stage: "plan", seat: "parked" })])
    expect(boardColumns(a).find((c) => c.name === "PLAN")!.items[0]!.state?.kind).toBe("parked")
  })
})

describe("epics on the TICKETS column", () => {
  const tk = (id: number, over: Partial<Ticket> = {}): Ticket => ({ id, workspace_id: 1, project_id: null, title: `k${id}`, priority: "normal", kind: "ticket", epic_id: null, ...over })
  const toy = tk(50, { title: "Toy", kind: "epic", done: 2, total: 13, next: { id: 52, title: "sandbox mode" } })
  const a = { ...snap([]), tickets: [toy, tk(52, { epic_id: 50, title: "sandbox mode" }), tk(53, { epic_id: 50 }), tk(46, { title: "profile" })] }
  test("one row per epic, its children hidden, loose tickets kept", () => {
    const items = boardColumns(a)[0]!.items
    expect(items.map((x) => x.title)).toEqual(["Toy 2/13 → #52 sandbox mode", "profile"])
    expect(items[0]!.act).toEqual({ kind: "epic", id: 50 })
  })
  test("an epic with no free child says so; opening one lists its children", () => {
    const quiet = { ...a, tickets: [{ ...toy, next: null }, ...a.tickets.slice(1)] }
    expect(boardColumns(quiet)[0]!.items[0]!.title).toBe("Toy 2/13")
    expect(epicChildren(a, 50).map((t) => t.id)).toEqual([52, 53])
  })
})

describe("initiatives on the TICKETS column", () => {
  const tk = (id: number, over: Partial<Ticket> = {}): Ticket => ({ id, workspace_id: 1, project_id: null, title: `k${id}`, priority: "normal", kind: "ticket", epic_id: null, ...over })
  const kids = tk(585, { title: "kids", kind: "initiative" })
  const toy = tk(50, { title: "Toy", kind: "epic", epic_id: 585, done: 2, total: 13, next: { id: 52, title: "sandbox mode" } })
  const hall = tk(60, { title: "Hall", kind: "epic", epic_id: 585, done: 1, total: 2, next: null })
  const a = { ...snap([]), tickets: [kids, toy, hall, tk(52, { epic_id: 50, title: "sandbox mode" }), tk(46, { title: "profile" })] }

  test("one row per initiative, its epics' progress summed and the first next step; its epics and tickets hidden", () => {
    const items = boardColumns(a)[0]!.items
    expect(items.map((x) => x.title)).toEqual(["kids 3/15 → #52 sandbox mode", "profile"])
    expect(items[0]!.act).toEqual({ kind: "epic", id: 585 })
    expect(items[0]!.stage).toBe("initiative")
  })

  test("an epic under no initiative is still its own row", () => {
    const loose = { ...a, tickets: [{ ...toy, epic_id: null }, ...a.tickets.filter((t) => t.id !== 50)] }
    expect(boardColumns(loose)[0]!.items.map((x) => x.title)).toContain("Toy 2/13 → #52 sandbox mode")
  })

  test("opening an initiative lists its epics, each with its progress", () => {
    expect(groupRows(a, 585)).toEqual([
      { id: 50, title: "Toy 2/13 → #52 sandbox mode", kind: "epic" },
      { id: 60, title: "Hall 1/2", kind: "epic" },
    ])
    expect(groupRows(a, 50)).toEqual([{ id: 52, title: "sandbox mode", kind: "ticket" }])
  })
})

describe("the TICKETS column as an expandable tree", () => {
  const tk = (id: number, over: Partial<Ticket> = {}): Ticket => ({ id, workspace_id: 1, project_id: null, title: `k${id}`, priority: "normal", kind: "ticket", epic_id: null, ...over })
  const kids = tk(585, { title: "kids", kind: "initiative" })
  const toy = tk(586, { title: "Toy", kind: "epic", epic_id: 585, done: 0, total: 2, next: { id: 590, title: "sandbox mode" } })
  const a = {
    ...snap([]),
    tickets: [kids, toy, tk(590, { epic_id: 586, title: "sandbox mode" }), tk(591, { epic_id: 586, title: "in flight", status: "doing", thread_id: 40 }), tk(7, { title: "loose" })],
  }
  const shape = (rows: ReturnType<typeof treeRows>) => rows.map((r) => [r.act.kind === "ticket" || r.act.kind === "epic" ? r.act.id : -1, r.depth, r.open])
  const ident = <T,>(xs: T[]) => xs

  test("collapsed, only the top level shows", () => {
    expect(shape(treeRows(a, new Set(), ident))).toEqual([
      [585, 0, false],
      [7, 0, false],
    ])
  })

  test("opening an initiative lists its epics one level down, collapsed", () => {
    expect(shape(treeRows(a, new Set([585]), ident))).toEqual([
      [585, 0, true],
      [586, 1, false],
      [7, 0, false],
    ])
  })

  test("opening an epic lists its children; an in-flight child is marked with its thread", () => {
    const rows = treeRows(a, new Set([585, 586]), ident)
    expect(shape(rows)).toEqual([
      [585, 0, true],
      [586, 1, true],
      [590, 2, false],
      [591, 2, false],
      [7, 0, false],
    ])
    expect(rows[3]!.flight).toBe(40)
    expect(rows[2]!.flight).toBeUndefined()
    expect(rows[1]!.title).toBe("Toy 0/2 → #590 sandbox mode · 1 in flight")
  })

  test("the order applies to each level on its own", () => {
    const reverse = <T,>(xs: T[]) => [...xs].reverse()
    expect(shape(treeRows(a, new Set([585, 586]), reverse))).toEqual([
      [7, 0, false],
      [585, 0, true],
      [586, 1, true],
      [591, 2, false],
      [590, 2, false],
    ])
  })
})

test("the whiteboard's legend words every mark the board can draw", () => {
  const marks = BOARD_LEGEND.map(([m]) => m)
  for (const g of Object.values(STATE_GLYPH)) expect(marks).toContain(g)
  expect(marks).toContain("■")
  for (const [, words] of BOARD_LEGEND) expect(words.length).toBeGreaterThan(5)
})

describe("the whiteboard's TICKETS sticky", () => {
  const tk = (id: number, over: Partial<Ticket> = {}): Ticket => ({ id, workspace_id: 1, project_id: null, title: `k${id}`, priority: "normal", kind: "ticket", epic_id: null, ...over })

  test("one line per initiative with its progress, then the loose tickets", () => {
    const a = {
      ...snap([]),
      tickets: [
        tk(585, { title: "kids", kind: "initiative" }),
        tk(586, { title: "Toy", kind: "epic", epic_id: 585, done: 0, total: 2, next: null }),
        tk(590, { title: "sandbox mode", epic_id: 586 }),
        tk(600, { title: "other", kind: "initiative" }),
        tk(7, { title: "one" }), tk(8, { title: "two" }), tk(9, { title: "three" }),
      ],
    }
    const lines = stickyItems(a)
    expect(lines.map((s) => s.text)).toEqual(["kids 0/2", "other 0/0", "3 loose"])
    expect(lines[0]!.act).toEqual({ kind: "epic", id: 585 })
    expect(lines[2]!.act).toEqual({ kind: "column", col: 0 })
  })

  test("a loose epic gets a line of its own, and no loose line without loose tickets", () => {
    const a = { ...snap([]), tickets: [tk(700, { title: "solo", kind: "epic", done: 1, total: 3, next: null })] }
    expect(stickyItems(a).map((s) => s.text)).toEqual(["solo 1/3"])
  })
})
