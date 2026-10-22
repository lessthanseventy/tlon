import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { baseLook, overrideFor, today } from "../kit/looks"
import type { DataPart } from "../kit/parts"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

type Inside = { hour: () => number; actors: Map<string, { look: { parts?: Record<string, { id: string } | undefined> } }> }
const inside = (r: WideRoom) => r as unknown as Inside
const room = () => {
  const r = new WideRoom(696), a = viewOf(office(2), 1)
  inside(r).hour = () => 16
  for (let i = 0; i < 20; i++) r.step(a)
  return { r, a }
}
const part: DataPart = { id: `gen:${today()}`, day: today(), slot: "head", front: { 2: "..yyyyyy...." }, side: { 2: "..yyyyyy...." }, back: { 2: "..yyyyyy...." } }
const toys = (parts: DataPart[]) => ({ visitors: [], puns: [], reactions: {}, parts })
const wearers = (r: WideRoom) => [...inside(r).actors.values()].filter((a) => a.look.parts?.head?.id === part.id).length

describe("the room dresses the day's wearer", () => {
  test("exactly one actor wears today's part, and it is nobody's saved look", () => seeded(7, () => {
    const { r, a } = room()
    r.setToys(toys([part])); r.step(a)
    expect(wearers(r)).toBe(1)
  }))
  test("no part, or a part from another day, is worn by nobody", () => seeded(7, () => {
    const { r, a } = room()
    r.setToys(toys([])); r.step(a); expect(wearers(r)).toBe(0)
    r.setToys(toys([{ ...part, id: "gen:2020-01-01", day: "2020-01-01" }])); r.step(a); expect(wearers(r)).toBe(0)
  }))
  test("clearing the toys undresses them", () => seeded(7, () => {
    const { r, a } = room()
    r.setToys(toys([part])); r.step(a)
    expect(wearers(r)).toBe(1)
    r.setToys(null); r.step(a)
    expect(wearers(r)).toBe(0)
  }))
  test("the override layer is untouched: overrideFor and baseLook never see the part", () => seeded(7, () => {
    const { r, a } = room()
    r.setToys(toys([part])); r.step(a)
    expect(wearers(r)).toBe(1)
    for (const name of inside(r).actors.keys()) {
      expect(overrideFor(name)?.parts?.head?.id).not.toBe(part.id)
      expect(baseLook(name).parts?.head?.id).not.toBe(part.id)
    }
  }))
})
