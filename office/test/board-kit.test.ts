import { expect, test } from "bun:test"
import { hitFor, idOf } from "../kit/board"
import type { BoardItem } from "../kit/crew"

const line = (over: Partial<BoardItem>): BoardItem => ({ act: { kind: "thread", tid: 7 }, title: "ship it", who: null, stage: "doing", asks: false, archetype: null, high: false, ...over })

test("a line's tip names its id, stage, person and what it waits on", () => {
  expect(hitFor(line({ who: "ada", asks: true })).tip).toBe("#7 ship it\ndoing · ada\nwaiting on you")
})

test("a column sticky's tip is its text alone", () => {
  const it = line({ act: { kind: "column", col: 0 }, stage: "" })
  expect(hitFor(it).tip).toBe("ship it")
  expect(idOf(it.act)).toBe(0)
})
