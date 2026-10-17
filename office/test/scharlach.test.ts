import { describe, expect, test } from "bun:test"
import { MUG, NAMEPLATE, SHERIFF, newLedger, tickRed, demerits, tickForRedThreads, tickFromTriage, ledgerLines } from "../kit/scharlach"

describe("Scharlach's desk dressing", () => {
  test("the nameplate and the mug say what the design says", () => {
    expect(NAMEPLATE).toBe("Sheriff (Assistant to the Manager)")
    expect(MUG).toBe("WORLD'S BEST SHERIFF")
    expect(SHERIFF).toBe("scharlach")
  })
})

describe("the demerit ledger", () => {
  test("ticks once per red build, per coworker", () => {
    let l = newLedger()
    expect(demerits(l, "yu")).toBe(0)
    l = tickRed(l, "yu")
    expect(demerits(l, "yu")).toBe(1)
    l = tickRed(l, "yu")
    expect(demerits(l, "yu")).toBe(2)
    // another coworker has their own tally
    l = tickRed(l, "tertius")
    expect(demerits(l, "tertius")).toBe(1)
    expect(demerits(l, "yu")).toBe(2)
  })
  test("a coworker with no red build has no demerits", () => {
    const l = tickRed(tickRed(newLedger(), "yu"), "yu")
    expect(demerits(l, "nolan")).toBe(0)
  })
  test("tickForRedThreads ticks each thread's lead once, from the snapshot's threads", () => {
    const threads = [
      { id: 1, lead: "yu" },
      { id: 2, lead: "tertius" },
      { id: 3, lead: "yu" },
    ] as { id: number; lead: string }[]
    // two red threads led by yu, one by tertius — yu ticks twice, tertius once
    const l = tickForRedThreads(newLedger(), [1, 2, 3], threads)
    expect(demerits(l, "yu")).toBe(2)
    expect(demerits(l, "tertius")).toBe(1)
  })
  test("a thread listed twice in one read (two failed checks) ticks once", () => {
    const l = tickForRedThreads(newLedger(), [7, 7], [{ id: 7, lead: "yu" }])
    expect(demerits(l, "yu")).toBe(1)
  })
  test("a thread already ticked this round is not ticked again", () => {
    const threads = [{ id: 1, lead: "yu" }] as { id: number; lead: string }[]
    let l = tickForRedThreads(newLedger(), [1], threads)
    expect(demerits(l, "yu")).toBe(1)
    // the same red, seen again next refresh, does not re-tick
    l = tickForRedThreads(l, [1], threads)
    expect(demerits(l, "yu")).toBe(1)
  })
  test("a red that clears then re-reds ticks again", () => {
    const threads = [{ id: 1, lead: "yu" }] as { id: number; lead: string }[]
    let l = tickForRedThreads(newLedger(), [1], threads)
    // red clears (no red ids) → the ticked memory drops it
    l = tickForRedThreads(l, [], threads)
    // red again → ticks once more
    l = tickForRedThreads(l, [1], threads)
    expect(demerits(l, "yu")).toBe(2)
  })
  test("a fully green board (triage count 0) clears the ticked memory, so a re-red ticks", () => {
    const threads = [{ id: 1, lead: "yu" }]
    let l = tickFromTriage(newLedger(), 1, [1], threads)
    l = tickFromTriage(l, 0, [], threads)
    l = tickFromTriage(l, 1, [1], threads)
    expect(demerits(l, "yu")).toBe(2)
  })
})

describe("the ledger on Scharlach's card", () => {
  test("empty reads a clean bill; each coworker with demerits gets a line", () => {
    const bench = [{ name: "yu" }, { name: "tertius" }]
    expect(ledgerLines(newLedger(), bench)).toEqual(["demerits: none — the office is behaving. For now."])
    let l = tickRed(tickRed(newLedger(), "yu"), "tertius")
    expect(ledgerLines(l, bench)).toEqual(["demerits:", "  yu 1", "  tertius 1"])
  })
})