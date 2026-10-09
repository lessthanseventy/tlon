import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { ARGOS } from "../kit/pets"
import { FIRE_GRACE } from "../kit/sim"
import { createHash } from "node:crypto"
import { closet, corner, WideRoom, widePlan, zones } from "../rooms/wide"
import { focus, measure, seeded } from "./golden"
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

describe("Argos in the smoke", () => {
  test("he leaves for the muster and barks smoke lines while it burns", () => {
    const r = new WideRoom(696) as any
    run(r, up, 300)
    const said = new Set<string>()
    for (let i = 0; i < FIRE_GRACE + 900; i++) { r.step(down()); if (r.dog.said) said.add(r.dog.said) }
    expect(r.dog.mode).not.toBe("sleep")
    expect(r.dog.y).toBeGreaterThan(160)
    expect([...said].some((s) => ARGOS.smoke.includes(s))).toBe(true)
  })
})

describe("Argos holds at the muster", () => {
  test("whatever the dice, he is still out there once the fire has burned a while", () => {
    for (let seed = 1; seed <= 20; seed++) seeded(seed, () => {
      const r = new WideRoom(696) as any
      r.hour = () => 3
      run(r, up, 300); run(r, down, FIRE_GRACE + 900)
      expect(r.dog.y, `seed ${seed}`).toBeGreaterThan(160)
    })
  }, 30_000)
})

describe("the server closet", () => {
  test("it stands clear of the furniture and the pastimes", () => {
    const z = zones(696), c = closet(), p = widePlan(696)
    const rects = [...p.blocks(p.layout(up())), ...Object.values(corner(z)).flat()]
    for (const q of rects) expect(c.x + c.w <= q.x || q.x + q.w <= c.x || c.y + c.h <= q.y || q.y + q.h <= c.y).toBe(true)
  })
  test("a burning room draws flames and smoke at the closet; a calm one does not", () => {
    const calm = new WideRoom(696), hot = new WideRoom(696), c = closet()
    run(calm, up, 300); run(hot, up, 300); run(hot, down, FIRE_GRACE + 5)
    const at = new Date(2026, 9, 9, 15)
    const patch = (r: WideRoom, f: typeof up) => {
      const fr = r.render(f(), focus, measure, at), out: number[] = []
      for (let y = c.y - 24; y < c.y + c.h; y++) for (let x = c.x - 4; x < c.x + c.w + 4; x++) out.push(...fr.rgba.slice((y * fr.width + x) * 4, (y * fr.width + x) * 4 + 4))
      return createHash("sha256").update(Buffer.from(out)).digest("hex")
    }
    expect(hot.onFire).toBe(true)
    expect(patch(hot, down)).not.toBe(patch(calm, up))
  })
})
