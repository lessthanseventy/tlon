import { describe, expect, test } from "bun:test"
import { dark, darkness, lampsLit } from "../kit/daylight"
import { Scene } from "../kit/draw"
import { bossDesk } from "../kit/furniture"
import { viewOf } from "../kit/crew"
import { EMPTY } from "../kit/types"
import { WideRoom } from "../rooms/wide"

describe("the light follows the clock", () => {
  test("full day at noon, full dark at 3am, a slope at dusk and dawn", () => {
    expect(darkness(12)).toBe(0)
    expect(darkness(3)).toBe(1)
    expect(darkness(19.5)).toBeGreaterThan(0)
    expect(darkness(19.5)).toBeLessThan(1)
    expect(darkness(6.75)).toBeGreaterThan(0)
    expect(darkness(6.75)).toBeLessThan(1)
    expect(darkness(20)).toBeGreaterThan(darkness(19))
    expect(darkness(7)).toBeLessThan(darkness(6.5))
  })

  test("lamps come on one by one as it darkens, all by night, none by day", () => {
    expect(lampsLit(12, 6)).toBe(0)
    expect(lampsLit(3, 6)).toBe(6)
    const lit = [18.5, 19, 19.5, 20, 20.5].map((h) => lampsLit(h, 6))
    expect(lit).toEqual([...lit].sort((p, q) => p - q))
    expect(new Set(lit).size).toBeGreaterThan(2)
  })

  test("dark is the hours of full dark: bedtime for the pets, clock-out for you", () => {
    expect(dark(23)).toBe(true)
    expect(dark(3)).toBe(true)
    expect(dark(12)).toBe(false)
    expect(dark(19)).toBe(false)
  })
})

const focus = { picked: null, armed: null, person: null }
const measure = (s: string) => s.length * 2
const at = (hour: number) => new Date(2026, 2, 6, hour, 0)
const lum = (rgba: Uint8Array) => { let s = 0; for (let i = 0; i < rgba.length; i += 4) s += rgba[i]! + rgba[i + 1]! + rgba[i + 2]!; return s / (rgba.length / 4) }

describe("the floor at night", () => {
  test("the floor is dimmer after dark than at noon", () => {
    const room = new WideRoom(560), a = viewOf({ ...EMPTY, ok: true }, 1)
    const day = lum(room.render(a, focus, measure, at(12)).rgba), night = lum(room.render(a, focus, measure, at(3)).rgba)
    expect(night).toBeLessThan(day * 0.85)
    expect(night).toBeGreaterThan(day * 0.4)
  })

  test("a lit lamp pools light: its patch is brighter, relatively, than the floor away from it", () => {
    const room = new WideRoom(560), a = viewOf({ ...EMPTY, ok: true }, 1), L0 = (room as unknown as { z: { L0: number } }).z.L0
    const patch = (f: { rgba: Uint8Array; width: number }, x: number, y: number) => {
      let s = 0
      for (let j = y; j < y + 8; j++) for (let i = x; i < x + 8; i++) { const o = (j * f.width + i) * 4; s += f.rgba[o]! + f.rgba[o + 1]! + f.rgba[o + 2]! }
      return s
    }
    const day = room.render(a, focus, measure, at(12)), night = room.render(a, focus, measure, at(3))
    const lamp = patch(night, L0 + 10, 62) / patch(day, L0 + 10, 62), away = patch(night, L0 + 60, 170) / patch(day, L0 + 60, 170)
    expect(lamp).toBeGreaterThan(away)
  })

  test("you wear pyjamas after dark: no tie, a different top", () => {
    const a = viewOf({ ...EMPTY, ok: true }, 1)
    const draw = (isDark: boolean) => { const sc = new Scene(100, 100, 0); sc.dark = isDark; bossDesk(sc, a, { x: 20, y: 20, w: 40 }); return Buffer.from(sc.finish().rgba).toString("hex") }
    expect(draw(true)).not.toBe(draw(false))
  })

  test("the pets go to sleep at bedtime, and not at noon", () => {
    const a = viewOf({ ...EMPTY, ok: true }, 1)
    type R = { hour: () => number; cat: { mode: string; until: number }; dog: { mode: string; until: number } }
    const run = (hour: number) => {
      const room = new WideRoom(560), r = room as unknown as R
      r.hour = () => hour
      for (const p of [r.cat, r.dog]) { p.mode = "sit"; p.until = 1e9 }
      const real = Math.random
      Math.random = () => 0.4
      try { for (let i = 0; i < 1_500; i++) room.step(a) } finally { Math.random = real }
      return [r.cat.mode, r.dog.mode]
    }
    expect(run(23)).toEqual(["sleep", "sleep"])
    expect(run(12)).not.toEqual(["sleep", "sleep"])
  })
})
