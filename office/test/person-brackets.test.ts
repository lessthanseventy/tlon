import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import type { Frame } from "../kit/canvas"
import type { Focus } from "../kit/draw"
import { type Agents } from "../kit/types"
import { RailRoom } from "../rooms/rail"
import { WideRoom } from "../rooms/wide"
import { measure, office } from "./golden"

/** w0 and w1 both on thread 102, as two coworkers share the lobby */
function shared(): Agents {
  const a = office(2)
  return { ...a, roster: a.roster.map((r) => (r.agent === "w1" ? { ...r, thread_id: 102 } : r)) }
}

const bracketed = (fr: Frame) => {
  const boxes = fr.ink.filter((i) => i.t === "brackets")
  return fr.hits
    .filter((h) => h.act.kind === "person" && boxes.some((b) => b.x === h.x && b.y === h.y && b.w === h.w && b.h === h.h))
    .map((h) => (h.act as { name: string }).name)
    .sort()
}

const rooms: [string, () => { step(a: Agents): void; render(a: Agents, f: Focus, m: typeof measure): Frame }][] = [
  ["wide", () => new WideRoom(640)],
  ["rail", () => new RailRoom()],
]

describe("picking a person brackets that person", () => {
  for (const [name, make] of rooms) {
    test(`${name}: a picked person is bracketed alone, a picked thread brackets everyone on it`, () => {
      const room = make(), a = viewOf(shared(), 1)
      for (let i = 0; i < 400; i++) room.step(a)
      const one = room.render(a, { picked: 102, armed: null, person: "w0" }, measure)
      expect(one.ink.filter((i) => i.t === "brackets").length).toBe(1)
      expect(bracketed(one)).toEqual(["w0"])
      const both = room.render(a, { picked: 102, armed: null, person: null }, measure)
      expect(bracketed(both)).toEqual(["w0", "w1"])
    })
  }
})
