import { expect, test } from "bun:test"
import { queueItems } from "../kit/rack"
import type { MergeItem } from "../kit/types"

const run = "#12 verify (pid 1) in /w since 21:49:17"
const w1 = "#13 landing (pid 2) in /w since 21:50:00"
const w2 = "mise run check:all (pid 3) in /v since 21:50:01"
const started = "2026-10-22T20:00:00Z", now = Date.parse("2026-10-22T20:03:30Z")
const gate = (pid: number | null) => ({ pid, started_at: started })
const car = (thread_id: number, pos: number, size: number, pid: number | null = 42): MergeItem =>
  ({ thread_id, title: `car ${thread_id}`, state: pos === 1 ? "landing" : "queued", train: { lead: 7, pos, size, split: false }, gate: gate(pid) })

test("a train is one block: its gate (the check it runs folded in), its cars in order with the lead marked, then who waits behind it", () => {
  const items = queueItems({
    checks: { running: "#9 landing car-9 (pid 42) in /w since 20:00:00", waiting: [w1] },
    merge_queue: [car(7, 1, 3), car(8, 2, 3), car(9, 3, 3),
      { thread_id: 5, title: "PR #61 chat-ux", state: "queued", train: "solo", gate: null },
      { thread_id: 4, title: "four", state: "queued", train: null, gate: null }],
  }, true, now)
  expect(items.map((i) => [i.kind, i.text])).toEqual([
    ["wait", w1],
    ["gate", "🚃 train → main  gate running 3m · pid 42"],
    ["car", "car 7"], ["car", "car 8"], ["car", "car 9"],
    ["next", "PR #61 chat-ux (PR · lands solo)"], ["next", "four (own turn)"],
    ["restart", "a restart is scheduled — it runs the moment nobody is mid-turn"],
  ])
  expect(items.filter((i) => i.kind === "car").map((i) => [i.thread_id, i.pos, i.lead])).toEqual([[7, 1, true], [8, 2, false], [9, 3, false]])
})

test("a check the gate doesn't own stays a check; a landing alone and a lead split off a red train say so", () => {
  const solo = queueItems({
    checks: { running: run, waiting: [] },
    merge_queue: [{ thread_id: 7, title: "seven", state: "landing", train: "solo", gate: gate(null) }],
  }, false, now)
  expect(solo.map((i) => [i.kind, i.text])).toEqual([["check", run], ["gate", "landing → main  gate running 3m"], ["car", "seven"]])

  const split = queueItems({
    checks: { running: null, waiting: [] },
    merge_queue: [{ thread_id: 7, title: "seven", state: "landing", train: { lead: 7, pos: 1, size: 1, split: true }, gate: gate(5) },
      { thread_id: 8, title: "eight", state: "queued", train: null, gate: null }],
  }, false, now)
  expect(split.map((i) => [i.kind, i.text])).toEqual([
    ["gate", "landing → main  split: lead lands alone  gate running 3m · pid 5"], ["car", "seven"], ["next", "eight (own turn)"],
  ])
})

test("a server that sends no trains still reads: its landing a gate of one, its queued their own turn", () => {
  const items = queueItems({
    checks: { running: run, waiting: [w2] },
    merge_queue: [{ thread_id: 7, title: "seven", state: "landing" }, { thread_id: 8, title: "eight", state: "queued" }],
  }, false, now)
  expect(items.map((i) => [i.kind, i.text])).toEqual([["check", run], ["wait", w2], ["gate", "landing → main  gate running"], ["car", "seven"], ["next", "eight (own turn)"]])
})

test("nothing queued and no restart pending is an empty list; a server too old to send queues is too", () => {
  expect(queueItems({ checks: { running: null, waiting: [] }, merge_queue: [] }, false)).toEqual([])
  expect(queueItems({}, false)).toEqual([])
})

test("a restart alone still shows, as status", () => {
  expect(queueItems({}, true).map((i) => i.kind)).toEqual(["restart"])
})
