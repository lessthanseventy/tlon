import { afterAll, expect, test } from "bun:test"

let hits = 0, sent: (string | null)[] = []
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    if (!new URL(req.url).pathname.endsWith("/office")) return new Response("no", { status: 404 })
    hits++
    sent.push(req.headers.get("if-none-match"))
    if (req.headers.get("if-none-match") === '"v1"') return new Response(null, { status: 304, headers: { etag: '"v1"' } })
    return Response.json({ roster: [], threads: [] }, { headers: { etag: '"v1"' } })
  },
})
afterAll(() => server.stop(true))

test("status asks with the last ETag and holds the same snapshot on a 304", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  data.useFake(null)
  const first = await data.status()
  const second = await data.status()
  expect(first.ok).toBe(true)
  expect(sent).toEqual([null, '"v1"'])
  expect(second).toBe(first)
  expect(hits).toBe(2)
})
