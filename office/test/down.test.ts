import { expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import type { Need } from "../tui/data"
import { downHeader } from "../tui/down"
import { focus, measure } from "./golden"
import { office } from "./wcag.test"

// the channel down is stale and honest: the last good snapshot and inbox held, marked down with
// their age and the verb that brings it back — never an empty office, and never the fire drill
const need: Need = { key: "gate:42", kind: "gate", level: "blocking", thread_id: 42, workspace_id: 1, title: "#42 waits on you", text: "approve?", at: "2026-10-13T06:00:00Z", options: null, ref: null }
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([need])
    if (path.endsWith("/office")) return Response.json({ threads: [{ id: 42, title: "the held thread", workspace_id: 1, stage: "review", awaiting: "andrew", lead: null }], workspaces: [{ id: 1, name: "Toy" }] })
    return new Response("no", { status: 404 })
  },
})

test("a down channel keeps the last snapshot and the inbox, held and dated", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}`
  const data = await import("../tui/data")
  expect((await data.status()).ok).toBe(true)
  expect(await data.needs()).toHaveLength(1)
  server.stop(true)

  const held = await data.status()
  expect(held.ok).toBe(false)
  expect(held.note).toContain("channel down")
  expect(held.heldAt).toBeGreaterThan(Date.now() - 60_000)
  expect(viewOf(held, 1).threads.map((t) => t.title)).toEqual(["the held thread"])
  expect(await data.needs()).toEqual([need])
})

test("the header says how old the view is and what brings the channel back", () => {
  const now = Date.now()
  expect(downHeader({ ...office(), ok: true }, now)).toBeNull()
  const line = downHeader({ ...office(), ok: false, note: "channel down (http://127.0.0.1:4040)", heldAt: now - 125_000 }, now)!
  expect(line).toContain("as of 2m ago")
  expect(line).toContain("mise run server:restart")
  // never up: nothing to hold, still the verb
  expect(downHeader({ ...office(), ok: false, note: "channel down (x)" }, now)).toContain("mise run server:restart")
})

test("an outage is not a fire drill: the room holds, dimmed, and nobody panics", () => {
  const room = new WideRoom(696), up = viewOf(office(), 1), down = viewOf({ ...office(), ok: false, note: "channel down" }, 1)
  const at = new Date(2026, 9, 9, 15)
  for (let i = 0; i < 300; i++) room.step(up)
  const lit = room.render(up, focus, measure, at)
  for (let i = 0; i < 2000; i++) room.step(down)
  expect(room.alarmed).toBe(false)
  const fr = room.render(down, focus, measure, at)
  const texts = fr.ink.flatMap((i) => (i.t === "text" && i.s ? [i.s] : []))
  expect(texts).not.toContain("FIRE DRILL")
  // dimmed: the floor is darker than it was with the channel up
  const sum = (f: typeof fr) => { let n = 0; for (let i = 0; i < f.rgba.length; i += 4) n += f.rgba[i]! + f.rgba[i + 1]! + f.rgba[i + 2]!; return n }
  expect(sum(fr)).toBeLessThan(sum(lit))
})
