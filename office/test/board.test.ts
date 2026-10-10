import { describe, expect, test } from "bun:test"
import { boardColumns, cardState, epicChildren } from "../kit/crew"
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
    expect(cardState(snap([]), thread(7, { prompt: { summary: "which one?" } }))?.why).toBe("asks: which one?")
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
  test("nobody leads it: no state to claim", () => {
    expect(cardState(snap([]), thread(7, { lead: null }))).toBeNull()
  })
  test("the board's thread cards carry their state; tickets don't", () => {
    const t = thread(7, { seat: "desk" })
    const a = { ...snap([t]), tickets: [{ id: 3, workspace_id: 1, project_id: null, title: "x", priority: "normal" }] }
    const cols = boardColumns(a)
    expect(cols[0]!.items[0]!.state).toBeUndefined()
    expect(cols[4]!.items[0]!.state?.kind).toBe("running")
  })
})

describe("who's doing what", () => {
  test("DOING is a plain thread someone is at a desk on — not one parked or idle", () => {
    const a = snap([thread(1, { stage: null, seat: "desk" }), thread(2, { stage: null, seat: "parked" }), thread(3, { stage: null })])
    expect(col(a, "DOING")).toEqual([1])
  })
  test("a standing duty is not work: off DOING and off the stage columns", () => {
    const a = snap([thread(1, { stage: null, seat: "desk", duty: true }), thread(2, { stage: "build", seat: "desk", duty: true }), thread(3, { seat: "parked" })])
    expect(col(a, "DOING")).toEqual([])
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
