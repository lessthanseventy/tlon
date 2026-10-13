import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { readTicks } from "../kit/sim"
import { EMPTY, type Agents } from "../kit/types"
import { WideRoom } from "../rooms/wide"

function office(names: string[]): Agents {
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: "builder", lead: i === 0, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `t${i}`, stage: null, awaiting: null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: false, thinking: false, workspace_id: 1 })),
  }
}
type Talk = { talk: Map<string, { text: string | null; until: number }> }

describe("banter you can read", () => {
  test("a line stays up long enough to read, ~10 s at the least and longer the longer it is", () => {
    expect(readTicks("ok")).toBeGreaterThanOrEqual(100)
    expect(readTicks("x".repeat(90))).toBeGreaterThan(readTicks("x".repeat(30)))
  })

  test("a conversation is said turn by turn: one balloon at a time, every turn, in order", () => {
    const room = new WideRoom(560), a = viewOf(office(["ada", "bo"]), 1), r = room as unknown as Talk
    room.converse([{ who: "ada", line: "first" }, { who: "bo", line: "second" }, { who: "ada", line: "third" }])
    const heard: string[] = []
    for (let i = 0; i < 2000; i++) {
      room.step(a)
      const up = [...r.talk.values()].flatMap((t) => (t.text ? [t.text] : []))
      expect(up.length).toBeLessThanOrEqual(1)
      if (up[0] && heard.at(-1) !== up[0]) heard.push(up[0])
    }
    expect(heard).toEqual(["first", "second", "third"])
  })

  test("a conversation doesn't take down a balloon it didn't put up", () => {
    const room = new WideRoom(560), a = viewOf(office(["ada", "bo"]), 1), r = room as unknown as Talk
    room.converse([{ who: "ada", line: "first" }, { who: "bo", line: "second" }])
    room.step(a)
    room.say("ada", "an answer to you, with words enough to stay up well past that turn")
    for (let i = 0; i < readTicks("first") + 2; i++) room.step(a)
    expect(r.talk.get("ada")?.text).toBe("an answer to you, with words enough to stay up well past that turn")
  })
})
