import { describe, expect, test } from "bun:test"
import { drawActors, Scene } from "../kit/draw"
import type { Actor, Kind } from "../kit/sim"
import { SEAT_VOICE, seatLine } from "../kit/seat-voices"
import { lookOf } from "../kit/sprites"
import { EMPTY } from "../kit/types"

const focus = { picked: null, person: null }
const POSED: Kind[] = ["aquarium", "chat", "pet", "vending", "foosball", "pool", "bathroom"]

function standing(kind: Kind, tick: number) {
  const sc = new Scene(48, 48, tick)
  const seat = { agent: "hronir", thread_id: 1, title: "", warm: false, thinking: false, doing: null, archetype: "builder" }
  const spot = { x: 24, y: 40, aisle: 44, pose: "stand" as const, face: "right" as const, kind }
  const actor: Actor = { seat, look: lookOf("hronir"), x: 24, y: 40, path: [], spot, spotKey: "", pose: "stand", face: "right", moving: false, until: 0, emote: null, emoteUntil: 0, leaving: false, doingSince: 0, stretch: 0, snack: 0, finished: -1000, five: 0, mug: 0, cooled: 0, warmth: 0 }
  drawActors(sc, [actor], new Map(), EMPTY, focus)
  return sc.finish().rgba.join()
}

describe("a coworker at a pastime", () => {
  test("each pastime has a pose of its own, and it moves", () => {
    const idle = standing("roam", 0)
    const seen = new Set<string>()
    for (const kind of POSED) {
      const a = standing(kind, 0)
      expect(a).not.toBe(idle)
      expect(standing(kind, 6)).not.toBe(a)
      expect(seen.has(a)).toBe(false)
      seen.add(a)
    }
  })
})

describe("a line for the place", () => {
  test("a seat's own line for a place comes up, and a seat with none says the plain-spoken builder's", () => {
    const own = new Set(SEAT_VOICE.scharlach!.at!.pool), generic = new Set(["Corner pocket. Watch this.", "Lining it up. Nobody breathe."])
    const lines = (name: string, place: string) => new Set(Array.from({ length: 300 }, () => seatLine(name, [], place)))
    expect([...lines("scharlach", "pool")].some((l) => own.has(l))).toBe(true)
    expect([...lines("tertius", "pool")].some((l) => generic.has(l))).toBe(true)
    expect([...lines("tertius", "pingpong")].some((l) => generic.has(l))).toBe(false)
  })
})
