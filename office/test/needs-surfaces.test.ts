import { afterAll, expect, test } from "bun:test"
import type { Need } from "../tui/data"

// the inbox by who acts: the server's phone, machine and clipboard; a server that only knows the
// flat list still reads, everything it sends without a surface on the phone so nothing hides
const at = "2026-10-21T06:00:00Z"
const need = (key: string, surface?: Need["surface"]): Need => ({ key, kind: "gate", level: "blocking", thread_id: 1, workspace_id: 1, title: key, text: key, at, options: null, ref: null, ...(surface ? { surface } : {}) })
const [a, b, c] = [need("gate:1", "phone"), need("mention:2", "machine"), need("issue:3", "clipboard")]
let body: unknown = { phone: [a], machine: [b], clipboard: [c], counts: { phone: 1, machine: 1, clipboard: 1 } }
let status = 200, query = "", heard: unknown = null
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const url = new URL(req.url)
    if (req.method === "POST" && url.pathname.endsWith("/office/needs/heard")) { heard = await req.json(); return Response.json({ ok: true }) }
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
  expect(r.counts).toEqual({ phone: 1, machine: 1, clipboard: 1 })
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
  expect(r.counts).toEqual({ phone: 1, machine: 1, clipboard: 1 })
  expect(r.phone).toEqual([bare])
})

test("hear posts the machine's keys", async () => {
  const data = await import("../tui/data")
  expect(await data.hear(["mention:2"])).toBe("heard")
  expect(heard).toEqual({ keys: ["mention:2"] })
})
