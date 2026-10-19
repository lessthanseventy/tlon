import { expect, test } from "bun:test"
import { rank, score } from "../tui/fuzzy"

const rows = [
  "settings: the running system's knobs",
  "pencils down: nothing new, everyone stops after their turn",
  "inbox: everything waiting on you",
  "Nina, the cat",
  "coworker nina  builder",
  "tickets & worklines: the board",
]

test("a name finds the rows it is in and not the rows its letters are scattered through", () => {
  expect(rank("nina", rows, (r) => r)).toEqual(["Nina, the cat", "coworker nina  builder"])
})

test("abbreviations at word starts and typos inside a word still match", () => {
  expect(score("ps", "pencils down: stops")).not.toBeNull()
  expect(score("worklines", "tickets & worklines: the board")).not.toBeNull()
  expect(score("tickets board", "tickets & worklines: the board")).not.toBeNull()
  expect(score("uncle", "uncle")).not.toBeNull()
})

test("every query letter still has to be there", () => {
  expect(score("xyz", "the clock")).toBeNull()
})
