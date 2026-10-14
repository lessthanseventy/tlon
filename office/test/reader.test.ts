import { expect, test } from "bun:test"
import { Reader } from "../tui/reader"

const msg = (id: number, author: string) => ({ id, author, body: `post ${id}`, at: "2026-10-12T10:00:00.000000Z", kind: "chat" })
const page = { messages: [msg(1, "ada"), msg(2, "bo"), msg(3, "ada")], peek: null, window: null }

test("keep filters what is shown, heading replaces the thread's title", () => {
  const r = new Reader(7, { load: async () => null, send: async () => "", operator: "andrew", redraw() {}, keep: (ms) => ms.filter((m) => m.author === "ada"), heading: "conversation with ada" }, false)
  r.take(page)
  const s = r.draw(60, 20, { id: 7, title: "lobby", stage: null, awaiting: null }, "")
  expect(s).toContain("post 1")
  expect(s).toContain("post 3")
  expect(s).not.toContain("post 2")
  expect(s).toContain("conversation with ada")
  expect(s).not.toContain("lobby")
})

test("the first esc leaves the reply box and keeps it drawn with its draft; the second leaves the reader", () => {
  const r = new Reader(7, { load: async () => null, send: async () => "", operator: "andrew", redraw() {} }, true)
  r.take(page)
  for (const ch of "half done") r.key(ch, 10)
  expect(r.key("esc", 10)).toBe("done")
  const s = r.draw(60, 20, { id: 7, title: "t", stage: null, awaiting: null }, "t look over their shoulder")
  expect(s).toContain("r or enter to write")
  expect(s).toContain("half done")
  expect(s).toContain("t look over their shoulder")
  expect(r.key("enter", 10)).toBe("done")
  expect(r.composer?.text).toBe("half done")
  r.key("esc", 10)
  expect(r.key("esc", 10)).toBe("leave")
})
