import { afterAll, expect, test } from "bun:test"

// a stand-in server: GET /office answers the snapshot, `revs` and `flags` included
const server = Bun.serve({
  port: 0,
  fetch: (req) =>
    new URL(req.url).pathname.endsWith("/office")
      ? Response.json({ roster: [], threads: [], revs: { office: "abc123" }, flags: { build_mode: true }, life: { "7": { level: 2, xp: 650, due: [] } } })
      : new Response("no", { status: 404 }),
})
afterAll(() => server.stop(true))

test("status carries the server's revs — what `R` compares to know the office is out of date — and its flags", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  const all = await data.status()
  expect(all.ok).toBe(true)
  expect(all.revs?.office).toBe("abc123")
  expect(all.flags).toEqual({ build_mode: true })
  expect(all.life).toEqual({ "7": { level: 2, xp: 650, due: [] } })
})
