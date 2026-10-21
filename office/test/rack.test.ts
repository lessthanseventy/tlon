import { expect, test } from "bun:test"
import { queueItems } from "../kit/rack"

const run = "#12 verify (pid 1) in /w since 21:49:17"
const w1 = "#13 landing (pid 2) in /w since 21:50:00"
const w2 = "mise run check:all (pid 3) in /v since 21:50:01"

test("one list: the running check, the waiters in ticket order, the landing, the queued, then the pending restart", () => {
  const items = queueItems({
    checks: { running: run, waiting: [w1, w2] },
    merge_queue: [{ thread_id: 7, title: "seven", state: "landing" }, { thread_id: 8, title: "eight", state: "queued" }],
  }, true)
  expect(items.map((i) => [i.kind, i.text])).toEqual([
    ["check", run], ["wait", w1], ["wait", w2],
    ["landing", "seven"], ["queued", "eight"],
    ["restart", "a restart is scheduled — it runs the moment nobody is mid-turn"],
  ])
  expect(items.filter((i) => i.thread_id).map((i) => i.thread_id)).toEqual([7, 8])
})

test("nothing queued and no restart pending is an empty list; a server too old to send queues is too", () => {
  expect(queueItems({ checks: { running: null, waiting: [] }, merge_queue: [] }, false)).toEqual([])
  expect(queueItems({}, false)).toEqual([])
})

test("a restart alone still shows, as status", () => {
  expect(queueItems({}, true).map((i) => i.kind)).toEqual(["restart"])
})
