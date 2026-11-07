import { expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

/** Nina and Argos idle on your office's floor, a chase started, and Argos' x and face every tick of it */
function chase(cat: { x: number; y: number }, dog: { x: number; y: number }) {
  return seeded(3, () => {
    const r = new WideRoom(696) as any, a = viewOf(office(4), 1)
    r.hour = () => 12
    for (let i = 0; i < 20; i++) r.step(a)
    Object.assign(r.cat, { ...cat, path: [], mode: "sit", until: 0 })
    Object.assign(r.dog, { ...dog, aisle: dog.y, path: [], mode: "sit", until: 0, fuss: null, belly: 0 })
    r.antic = null; r.turns = []; r.tick += 20 - (r.tick % 20)
    const random = Math.random, rolls = [0.01, 0.5]
    Math.random = () => rolls.shift() ?? random()
    try { r.stepAntics() } finally { Math.random = random }
    expect(r.antic?.kind).toBe("chase")
    const xs: number[] = [], faces: number[] = []
    while (r.antic?.kind === "chase") { r.step(a); xs.push(r.dog.x); faces.push(r.dog.face) }
    return { xs, faces }
  })
}

test("in a chase Argos runs after Nina round the room, never back and forth along one wall", () => {
  const { xs } = chase({ x: 26, y: 104 }, { x: 20, y: 104 })
  const steps = xs.slice(1).map((x, i) => Math.sign(x - xs[i]!)).filter(Boolean)
  expect(steps.slice(1).filter((s, i) => s !== steps[i]).length).toBe(0)
})

test("Argos faces the way he runs", () => {
  const { xs, faces } = chase({ x: 50, y: 104 }, { x: 44, y: 104 })
  xs.slice(1).forEach((x, i) => { if (x !== xs[i]) expect(faces[i + 1]).toBe(Math.sign(x - xs[i]!)) })
})
