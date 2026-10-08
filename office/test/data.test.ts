import { afterAll, expect, test } from "bun:test"

// a stand-in server: GET /office answers the snapshot, `revs` included
const server = Bun.serve({
  port: 0,
  fetch: (req) =>
    new URL(req.url).pathname.endsWith("/office")
      ? Response.json({ roster: [], threads: [], revs: { office: "abc123" } })
      : new Response("no", { status: 404 }),
})
afterAll(() => server.stop(true))

test("status carries the server's revs — what `R` compares to know the office is out of date", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  const all = await data.status()
  expect(all.ok).toBe(true)
  expect(all.revs?.office).toBe("abc123")
})
