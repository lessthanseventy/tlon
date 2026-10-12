import { describe, expect, test } from "bun:test"
import { earmarkOf } from "../kit/plane"
import { Reader } from "../tui/reader"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office, seeded } from "./golden"

const msg = (id: number, author: string) => ({ id, author, body: `post ${id}`, at: `2026-10-12T10:0${id}:00.000000Z`, kind: "chat" })
const page = { messages: [msg(1, "uqbar"), msg(2, "uqbar"), msg(3, "w0")], peek: null, window: null }
const screen = (dogeared?: (m: { at: string; author: string }) => boolean) => {
  const r = new Reader(7, { load: async () => null, send: async () => "", operator: "andrew", redraw() {}, dogeared })
  r.take(page)
  return r.draw(60, 20, undefined, "")
}
const marks = (s: string) => s.split("🐾").length - 1

describe("the dog-ear", () => {
  test("a post Argos caught shows 🐾 on its header, and only that post", () => {
    const s = screen((m) => m.at === page.messages[1]!.at && m.author === "uqbar")
    expect(marks(s)).toBe(1)
    const rows = s.split(/\x1b\[\d+;1H/).filter((x) => x.includes("🐾"))
    expect(rows[0]).toContain("uqbar")
  })
  test("nothing caught: the thread is as it was", () => {
    expect(marks(screen())).toBe(0)
    expect(marks(screen(() => false))).toBe(0)
  })
  test("an earmark names the thread, the moment and who posted", () => {
    expect(earmarkOf(7, "2026-10-12T10:02:00.000000Z", "uqbar")).not.toBe(earmarkOf(8, "2026-10-12T10:02:00.000000Z", "uqbar"))
    expect(earmarkOf(7, "2026-10-12T10:02:00.000000Z", "uqbar")).not.toBe(earmarkOf(7, "2026-10-12T10:03:00.000000Z", "uqbar"))
  })
})

describe("the room says which plane Argos caught", () => {
  test("fly returns true for every 4th plane", () => {
    seeded(3, () => {
      const room = new WideRoom(696), v = viewOf(office(3), 1)
      room.render(v, focus, measure, new Date(2026, 9, 5, 21, 0))
      for (let i = 0; i < 300; i++) room.step(v)
      expect([0, 1, 2, 3, 4].map(() => room.fly(102, v))).toEqual([false, false, false, true, false])
    })
  })
})
