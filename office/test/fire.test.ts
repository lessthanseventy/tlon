import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { FIRE_GRACE } from "../kit/sim"
import { WideRoom } from "../rooms/wide"
import { office } from "./wcag.test"

const up = () => viewOf(office(), 1)
const down = () => viewOf({ ...office(), ok: false, note: "channel down" }, 1)
const run = (r: WideRoom, f: () => ReturnType<typeof up>, n: number) => { for (let i = 0; i < n; i++) r.step(f()) }

describe("fire drill", () => {
  test("a short blip is not a fire; a held outage is; recovery puts it out", () => {
    const r = new WideRoom(696)
    run(r, up, 20)
    run(r, down, FIRE_GRACE - 5)
    expect(r.onFire).toBe(false)
    run(r, up, 1); run(r, down, FIRE_GRACE - 5)
    expect(r.onFire).toBe(false)
    run(r, down, 10)
    expect(r.onFire).toBe(true)
    run(r, up, 1)
    expect(r.onFire).toBe(false)
  })
  test("a room that never saw the channel up does not burn", () => {
    const r = new WideRoom(696)
    run(r, down, FIRE_GRACE * 2)
    expect(r.onFire).toBe(false)
  })
})

describe("the drill", () => {
  test("on fire, everyone ends at a muster spot holding a mug; all distinct; they return after", () => {
    const r = new WideRoom(696) as any
    run(r, up, 300)
    run(r, down, FIRE_GRACE + 1200)
    const actors = [...r.actors.values()] as any[]
    expect(actors.length).toBeGreaterThan(0)
    for (const a of actors) { expect(a.spot.kind).toBe("exit"); expect(a.moving).toBe(false); expect(a.mug).toBeGreaterThan(r.tick) }
    expect(new Set(actors.map((a) => `${a.x}:${a.y}`)).size).toBe(actors.length)
    run(r, up, 1500)
    for (const a of r.actors.values()) expect(a.spot.kind).not.toBe("exit")
  })
})
