import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { ROLE } from "../kit/palette"
import { DRILL, PANIC } from "../kit/sim"
import { closet, WideRoom } from "../rooms/wide"
import { focus, measure, seeded } from "./golden"
import { office } from "./wcag.test"

const up = () => viewOf(office(), 1)
const run = (r: WideRoom, n: number) => { for (let i = 0; i < n; i++) r.step(up()) }
const hex = (c: string) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16))

describe("a fire drill is a panic, then a muster", () => {
  test("the crew scatters over the room before anyone files out", () => seeded(7, () => {
    const r = new WideRoom(696) as any
    run(r, 300)
    r.play("drill")
    run(r, 150)
    const actors = [...r.actors.values()] as any[]
    expect(actors.length).toBeGreaterThan(3)
    expect(actors.filter((a) => a.spot.kind === "panic").length).toBeGreaterThanOrEqual(Math.ceil(actors.length / 2))
    expect(new Set(actors.map((a) => `${a.spot.x}:${a.spot.y}`)).size).toBeGreaterThan(actors.length / 2)
    run(r, PANIC + 250 - 150)
    for (const a of r.actors.values()) expect(a.spot.kind).toBe("exit")
    run(r, DRILL + 900)
    for (const a of r.actors.values()) expect(a.spot.kind).not.toBe("exit")
  }))

  test("a drill during a running scene is refused, not stacked on top of it", () => seeded(3, () => {
    const r = new WideRoom(696) as any
    run(r, 300)
    expect(r.event("duck")).toBe(true)
    run(r, 10)
    r.play("drill")
    expect(r.alarmed).toBe(false)
    expect(r.eventNow()?.kind).toBe("duck")
  }))

  test("they scream, but a handful of lines, not one per person per tick", () => seeded(3, () => {
    const r = new WideRoom(696) as any
    run(r, 300)
    let said = 0
    const say = r.say.bind(r)
    r.say = (who: string, text: string | null) => { said++; say(who, text) }
    r.play("drill")
    run(r, DRILL)
    expect(said).toBeGreaterThanOrEqual(3)
    expect(said).toBeLessThanOrEqual(12)
  }))

  test("a keyed drill sets the rack on fire for its length: flames above the closet, then out", () => seeded(11, () => {
    const r = new WideRoom(696) as any, c = closet(), at = new Date(2026, 9, 9, 15)
    run(r, 300)
    const flame = () => {
      const fr = r.render(up(), focus, measure, at), [br, bg, bb] = hex(ROLE.body)
      let n = 0
      for (let y = c.y - 12; y < c.y + c.h; y++) for (let x = c.x; x < c.x + c.w; x++) {
        const i = (y * fr.width + x) * 4
        if (fr.rgba[i] === br && fr.rgba[i + 1] === bg && fr.rgba[i + 2] === bb) n++
      }
      return n
    }
    // amber that isn't fire (Argos trotting past) is counted too: the flames are measured against a calm frame
    const calm = flame()
    r.play("drill"); run(r, 10)
    expect(r.alarmed).toBe(true)
    expect(flame()).toBeGreaterThan(calm + 10)
    run(r, DRILL)
    expect(r.alarmed).toBe(false)
    expect(flame()).toBeLessThan(calm + 10)
  }))
})

test("Nina has the zoomies for the whole panic, asleep or not", () => seeded(5, () => {
  const r = new WideRoom(696) as any
  run(r, 300)
  r.catDo("nap"); run(r, 200)
  r.play("drill")
  let zooming = 0
  for (let i = 0; i < PANIC; i++) { r.step(up()); if (r.cat.mode === "zoom") zooming++ }
  expect(zooming).toBeGreaterThan(PANIC * 0.7)
}))
