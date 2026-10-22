import { afterAll, expect, test } from "bun:test"
import type { Need } from "../tui/data"

// the inbox by who acts: the server's phone, machine and clipboard; a server that only knows the
// flat list still reads, everything it sends without a surface on the phone so nothing hides
const at = "2026-10-21T06:00:00Z"
const need = (key: string, surface?: Need["surface"]): Need => ({ key, kind: "gate", level: "blocking", thread_id: 1, workspace_id: 1, title: key, text: key, at, options: null, ref: null, ...(surface ? { surface } : {}) })
const [a, b, c] = [need("gate:1", "phone"), need("mention:2", "machine"), need("issue:3", "clipboard")]
let body: unknown = { phone: [a], machine: [b], clipboard: [c], counts: { phone: 1, machine: 1, clipboard: 1 } }
let status = 200, query = "", heard: unknown = null, overruled: unknown = null, posted: unknown = null
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const url = new URL(req.url)
    if (req.method === "POST" && url.pathname.endsWith("/office/needs/heard")) { heard = await req.json(); return Response.json({ ok: true }) }
    if (req.method === "POST" && url.pathname.endsWith("/office/needs/overrule")) { overruled = await req.json(); return Response.json({ key: "question:6" }) }
    if (req.method === "POST" && url.pathname.endsWith("/messages")) { posted = { path: url.pathname, body: await req.json() }; return Response.json({ id: 1 }) }
    if (url.pathname.endsWith("/office/needs")) { query = url.search; return status === 200 ? Response.json(body) : new Response("gone", { status }) }
    return new Response("no", { status: 404 })
  },
})
afterAll(() => server.stop(true))

test("needs reads the list by surface: every item in order, phone first, and the counts", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}`
  const data = await import("../tui/data")
  const r = await data.needs()
  expect(query).toBe("?by=surface")
  expect(r.items).toEqual([a, b, c])
  expect(r.counts).toEqual({ phone: 1, machine: 1, clipboard: 1, uqbar: 0, settled: 0 })
  expect(r.machine).toEqual([b])

  status = 500
  expect(await data.needs()).toEqual(r)
  status = 200
})

test("a server with only the flat list: grouped by what each item says, no surface on the phone", async () => {
  const data = await import("../tui/data")
  const bare = need("gate:9")
  body = [bare, b, c]
  const r = await data.needs()
  expect(r.items).toEqual([bare, b, c])
  expect(r.counts).toEqual({ phone: 1, machine: 1, clipboard: 1, uqbar: 0, settled: 0 })
  expect(r.phone).toEqual([bare])
})

test("hear posts the machine's keys", async () => {
  const data = await import("../tui/data")
  expect(await data.hear(["mention:2"])).toBe("heard")
  expect(heard).toEqual({ keys: ["mention:2"] })
})

test("a tool refusal handed to Uqbar is a post to it on the thread, never a hand-off", async () => {
  const data = await import("../tui/data")
  expect(await data.refusalToUqbar(7, "nolan was refused Bash 2 times")).toBe("#7: Uqbar asked to decide")
  expect(posted).toEqual({ path: "/api/threads/7/messages", body: { body: "@uqbar decide this tool refusal for me: nolan was refused Bash 2 times" } })
})

test("overrule posts the settled item's key", async () => {
  const data = await import("../tui/data")
  expect(await data.overrule("question:6")).toBe("back with Uqbar")
  expect(overruled).toEqual({ key: "question:6" })
})

test("Uqbar's queue and the settled digest ride along, counted apart; an older server sends neither", async () => {
  const data = await import("../tui/data")
  const [u1, u2] = [need("issue:4", "clipboard"), need("issue:5", "clipboard")]
  const s = { ...need("question:6", "phone"), why: "dup of #12" }
  body = { phone: [a], machine: [b], clipboard: [c], uqbar: [u1, u2], settled: [s], counts: { phone: 1, machine: 1, clipboard: 1, uqbar: 2, settled: 1 } }
  const r = await data.needs()
  expect(r.uqbar).toEqual([u1, u2])
  expect(r.settled).toEqual([s])
  expect(r.counts).toEqual({ phone: 1, machine: 1, clipboard: 1, uqbar: 2, settled: 1 })
  expect(r.items).toEqual([a, b, c])

  body = { phone: [a], machine: [b], clipboard: [c], counts: { phone: 1, machine: 1, clipboard: 1 } }
  const old = await data.needs()
  expect(old.uqbar).toEqual([])
  expect(old.settled).toEqual([])
  expect(old.counts).toEqual({ phone: 1, machine: 1, clipboard: 1, uqbar: 0, settled: 0 })
})
