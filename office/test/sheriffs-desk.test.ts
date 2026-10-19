import { expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { NAMEPLATE } from "../kit/scharlach"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office } from "./golden"

const at = new Date(2026, 9, 5, 21, 0)
const texts = (ink: { t: string; s?: string }[]) => ink.flatMap((i) => (i.t === "text" && i.s ? [i.s] : []))
const plates = (ink: { t: string; s?: string }[]) => texts(ink).filter((s) => NAMEPLATE.startsWith(s.replace(/\.$/, "").slice(0, 7)) && s.startsWith("Sheriff"))

function frame(sheriff: boolean) {
  const o = JSON.parse(JSON.stringify(office(4)).replaceAll('"w3"', sheriff ? '"scharlach"' : '"w3"')) as ReturnType<typeof office>
  const room = new WideRoom(560), a = viewOf(o, 1)
  for (let i = 0; i < 30; i++) room.step(a)
  return room.render(a, focus, measure, at)
}

test("the nameplate is on the sheriff's desk, and on no one else's", () => {
  expect(plates(frame(true).ink)).toHaveLength(1)
  expect(plates(frame(false).ink)).toHaveLength(0)
})
