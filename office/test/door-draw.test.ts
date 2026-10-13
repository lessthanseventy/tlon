import { describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office } from "./golden"

describe("the front door, drawn", () => {
  const room = new WideRoom(696), a = viewOf(office(2), 1)
  const frame = () => createHash("sha256").update(Buffer.from(room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0)).rgba)).digest("hex")
  test("a visitor in the doorway changes the frame; so does the bell; both go away again", () => {
    for (let i = 0; i < 5; i++) room.step(a)
    const base = frame()
    const r = room as unknown as { caller: unknown; tick: number }
    r.caller = { kind: "cookies", who: "tertius", bell: r.tick + 5, here: -1 }
    const ringing = frame()
    r.caller = { kind: "cookies", who: "tertius", bell: r.tick - 1, here: r.tick }
    const open = frame()
    const kinds = (["carrier", "pizza", "tourist"] as const).map((k) => { r.caller = { kind: k, who: "tertius", bell: 0, here: r.tick }; return frame() })
    r.caller = null
    expect(ringing).not.toBe(base)
    expect(open).not.toBe(ringing)
    expect(new Set([open, ...kinds]).size).toBe(4)
    expect(frame()).toBe(base)
  })
})
