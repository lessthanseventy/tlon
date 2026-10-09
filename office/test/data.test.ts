import { afterAll, expect, test } from "bun:test"

// a stand-in server: GET /office answers the snapshot, `revs` and `flags` included
const lifeBody = { xp: 650, level: 2, next_level_at: 900, streaks: { "1": 3 }, due: [{ routine_id: 1, title: "teeth", due_at: "2026-10-08T07:00:00Z", window_remaining: 600 }], quests: [{ id: 5, title: "book dentist", due_at: null, xp: 20 }], today: [] }
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], revs: { office: "abc123" }, flags: { build_mode: true }, life: { "7": { level: 2, xp: 650, due: [] } } })
    if (req.method === "GET" && path.endsWith("/life/7")) return Response.json(lifeBody)
    if (req.method === "POST" && path.endsWith("/life/routines/1/done")) return Response.json({ run: {}, level_up: true })
    return new Response("no", { status: 404 })
  },
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

test("life reads the card's body and a stamp reports a level-up", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  expect((await data.life(7))?.level).toBe(2)
  expect(await data.routineDone(1, "teeth")).toContain("level up")
})

test("a fake source answers every call; a write says it's a toy", async () => {
  const data = await import("../tui/data")
  const { toy } = await import("../tui/sandbox")
  data.useFake(toy())
  try {
    const all = await data.status()
    expect(all.ok).toBe(true); expect(all.bench.length).toBeGreaterThan(3)
    expect(await data.needs()).toEqual([])
    expect(await data.ticketFile(1, "x")).toContain("toy")
  } finally { data.useFake(null) }
})
