import { describe, expect, test } from "bun:test"
import { crewOf, peopleOf, viewOf } from "../kit/crew"
import { office } from "./golden"

const withUqbar = (thinking = false) => {
  const a = office(3)
  return { ...a, roster: [...a.roster, { agent: "uqbar", thread_id: 101, title: "t1", warm: false, thinking, workspace_id: 1 }] }
}

describe("uqbar in the view", () => {
  test("is lifted out of the roster: no desk, no crew row, no person", () => {
    const v = viewOf(withUqbar(), 1)
    expect(v.uqbar).toMatchObject({ agent: "uqbar", thread_id: 101 })
    expect(v.roster.some((r) => r.agent === "uqbar")).toBe(false)
    expect(crewOf(v).some((c) => c.name === "uqbar")).toBe(false)
    expect(peopleOf(v).some((p) => p.agent === "uqbar")).toBe(false)
  })
  test("is seen from any workspace, and absent without a session", () => {
    expect(viewOf(withUqbar(), 2).uqbar).not.toBeNull()
    expect(viewOf(office(3), 1).uqbar).toBeNull()
  })
})
