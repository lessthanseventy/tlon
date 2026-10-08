import { describe, expect, test } from "bun:test"
import { boardColumns, cardState } from "../kit/crew"
import { EMPTY, type Agents, type Seat, type Thread } from "../kit/types"

const thread = (id: number, over: Partial<Thread> = {}): Thread => ({ id, title: `t${id}`, stage: "build", awaiting: null, workspace_id: 1, lead: "ireneo", ...over })
const seat = (thread_id: number, over: Partial<Seat> = {}): Seat => ({ agent: "ireneo", thread_id, title: "", warm: false, workspace_id: 1, ...over })
const snap = (threads: Thread[], roster: Seat[] = []): Agents => ({ ...EMPTY, ok: true, threads, roster })

describe("a workline card's state", () => {
  test("running: its lead has a warm or mid-turn session on it", () => {
    const t = thread(7)
    expect(cardState(snap([t], [seat(7, { warm: true })]), t)?.kind).toBe("running")
    expect(cardState(snap([t], [seat(7, { thinking: true })]), t)?.kind).toBe("running")
  })
  test("parked: staffed, but its lead has no session on it — waiting for them", () => {
    const t = thread(7)
    expect(cardState(snap([t], [seat(7, { agent: "daneri", warm: true })]), t)).toEqual({ kind: "parked", why: "waiting for ireneo" })
    expect(cardState(snap([t], [seat(7)]), t)).toEqual({ kind: "parked", why: "waiting for ireneo" })
  })
  test("parked at the leaf cap: waiting for a slot, with the count", () => {
    const t = thread(7), busy = [thread(1, { live: true }), thread(2, { live: true }), thread(3, { live: true, standing: true })]
    expect(cardState(snap([t, ...busy]), t, { maxLeaves: 2 })).toEqual({ kind: "parked", why: "waiting for a slot (2/2)", atCap: true })
    expect(cardState(snap([t, ...busy]), t, { maxLeaves: 3 })).toEqual({ kind: "parked", why: "waiting for ireneo" })
  })
  test("needs you: it awaits the operator, asks something, or is on the needs list — before anything else", () => {
    expect(cardState(snap([]), thread(7, { awaiting: "spec approval" }))).toEqual({ kind: "needs", why: "awaits spec approval" })
    expect(cardState(snap([]), thread(7, { prompt: { summary: "which one?" } }))?.why).toBe("asks: which one?")
    const t = thread(7)
    expect(cardState(snap([t], [seat(7, { thinking: true })]), t, { needs: [7] })?.kind).toBe("needs")
  })
  test("nobody leads it: no state to claim", () => {
    expect(cardState(snap([]), thread(7, { lead: null }))).toBeNull()
  })
  test("the board's thread cards carry their state; tickets don't", () => {
    const t = thread(7)
    const a = { ...snap([t], [seat(7, { warm: true })]), tickets: [{ id: 3, workspace_id: 1, project_id: null, title: "x", priority: "normal" }] }
    const cols = boardColumns(a)
    expect(cols[0]!.items[0]!.state).toBeUndefined()
    expect(cols[4]!.items[0]!.state?.kind).toBe("running")
  })
})
