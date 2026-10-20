import { expect, test } from "bun:test"
import { pointAt, STEP } from "../kit/aleph"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

test("the Aleph's amber point hops while it reads, then settles", () => {
  const v = { tid: 1, since: 0, leaving: null }
  const early = new Set(Array.from({ length: 40 }, (_, t) => JSON.stringify(pointAt(v, t))))
  expect(early.size).toBeGreaterThan(3)
  expect(pointAt(v, 500)).toEqual(pointAt(v, 900))
})

test("it comes when its session appears, says so, and goes when the session ends", () => seeded(1, () => {
  const o = office(4), room: any = new WideRoom(696)
  room.hour = () => 12
  const called = viewOf({ ...o, roster: [...o.roster, { agent: "aleph", thread_id: o.threads[2]!.id, title: "", warm: true, thinking: true, workspace_id: 1 }] }, 1)
  const quiet = viewOf(o, 1)
  expect(called.aleph?.agent).toBe("aleph")
  expect(called.roster.some((r) => r.agent === "aleph")).toBe(false) // never a person at a desk

  room.step(called)
  expect(room.visit).toMatchObject({ tid: o.threads[2]!.id, leaving: null })
  expect(room.alephSaid.text).toContain("Show me where it bends")
  for (let i = 0; i < 100; i++) room.step(called)

  room.step(quiet)
  expect(room.visit.leaving).not.toBeNull()
  expect(room.alephSaid.text).toContain("standing in the wrong place")
  for (let i = 0; i < STEP * 3 + 60; i++) room.step(quiet)
  expect(room.visit).toBeNull()
}))
