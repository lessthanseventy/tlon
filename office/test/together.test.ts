import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { office } from "./golden"

// Two people the room sees together are handed to `onTogether` — each conversation its own model call
type Seen = { actors: Map<string, { seat: { agent: string }; spot: { kind: string }; moving: boolean; path: unknown[]; x: number; y: number }>; tick: number }

describe("who the room sees together", () => {
  test("two settled at the same game get talking; one alone, or none asked, says nothing", () => {
    const room = new WideRoom(640), a = viewOf(office(2), 1), r = room as unknown as Seen
    const heard: [string, string, string][] = []
    room.onTogether = (s, x, y) => heard.push([s, x, y])
    const real = Math.random
    Math.random = () => 0
    try {
      room.step(a)
      const [p, q, ...rest] = [...r.actors.values()]
      rest.forEach((x, i) => { x.moving = true; x.x = 1000 * (i + 1); x.y = 0 })
      for (const x of [p!, q!]) { x.spot = { ...x.spot, kind: "pingpong" }; x.moving = false; x.path = [] }
      while (r.tick % 40 !== 39) room.step(a)
      room.step(a)
    } finally { Math.random = real }
    expect(heard.length).toBe(1)
    expect(heard[0]![0]).toBe("pingpong")
  })
})
