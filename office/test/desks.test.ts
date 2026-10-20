import { expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { layoutFor, zones } from "../rooms/wide"
import { office } from "./golden"

const chairs = (a: ReturnType<typeof office>) => layoutFor(zones(560))(viewOf(a, 1)).chairs.map((c) => c.agent)

test("the eight chairs go to whoever has a live session first, the bench order after", () => {
  // ten builders, only w9 (last on the bench) with a session: w9 sits; the bench order fills the rest
  const a = office(10)
  a.roster = a.roster.filter((r) => ["tertius", "hronir", "w9"].includes(r.agent))
  expect(chairs(a)).toEqual(["w9", "w0", "w1", "w2", "w3", "w4", "w5", "w6"])
})

test("a turn ending moves nobody: a session between turns keeps its chair", () => {
  const a = office(10)
  a.roster = a.roster.filter((r) => ["tertius", "hronir", "w9"].includes(r.agent)).map((r) => ({ ...r, thinking: false }))
  expect(chairs(a)[0]).toBe("w9")
})
