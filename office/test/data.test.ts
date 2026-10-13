import { afterAll, expect, test } from "bun:test"

// a stand-in server: GET /office answers the snapshot, `revs` and `flags` included
const lifeBody = { xp: 650, level: 2, next_level_at: 900, streaks: { "1": 3 }, due: [{ routine_id: 1, title: "teeth", due_at: "2026-10-08T07:00:00Z", window_remaining: 600 }], quests: [{ id: 5, title: "book dentist", due_at: null, xp: 20 }], today: [] }
let resolved: unknown = null
let answered: unknown = null
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [{ id: 2, title: "lobby", standing: true, workspace_id: 1 }, { id: 3, title: "lobby notes", standing: false, workspace_id: 1 }], revs: { office: "abc123" }, release: { sha: "0f00bar", cut_at: "2026-10-12T20:00:00Z" }, flags: { build_mode: true }, life: { "7": { level: 2, xp: 650, due: [] } } })
    if (req.method === "GET" && path.endsWith("/life/7")) return Response.json(lifeBody)
    if (req.method === "GET" && path.endsWith("/office/margin/1")) return Response.json([{ id: 1, author: "uqbar", body: "cut 650fa4a", at: 5 }])
    if (req.method === "GET" && path.endsWith("/office/margin/2")) return new Response("boom", { status: 500 })
    if (req.method === "POST" && path.endsWith("/life/routines/1/done")) return Response.json({ run: {}, level_up: true })
    if (req.method === "POST" && path.endsWith("/issues/32/fix")) return Response.json({ ticket_id: 400, owner: "routed to tertius" })
    if (req.method === "POST" && path.endsWith("/office/prompts/9")) return req.json().then((b) => { answered = b; return Response.json({ ok: true, message_id: 10 }) })
    if (req.method === "POST" && path.endsWith("/issues/31/resolve")) return req.json().then((b) => { resolved = b; return Response.json({ resolved: 31 }) })
    if (req.method === "POST" && path.endsWith("/threads/44/rebase")) return Response.json({ rebased: 44 }, { status: 202 })
    if (req.method === "POST" && path.endsWith("/threads/44/reland")) return Response.json({ relanded: 44 }, { status: 202 })
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
  expect(all.release).toEqual({ sha: "0f00bar", cut_at: "2026-10-12T20:00:00Z" })
  expect(all.life).toEqual({ "7": { level: 2, xp: 650, due: [] } })
})

test("the standing thread is the front desk in the room, not \"lobby\"", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  const all = await data.status()
  expect(all.threads.find((t) => t.id === 2)?.title).toBe("the front desk")
  expect(all.threads.find((t) => t.id === 3)?.title).toBe("lobby notes")
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

test("margin reads Uqbar's notes; a 500 and a dead server are an empty margin", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  expect(await data.margin(1)).toEqual([{ id: 1, author: "uqbar", body: "cut 650fa4a", at: 5 }])
  expect(await data.margin(2)).toEqual([])
  process.env.TLON_URL = "http://127.0.0.1:1/api"
  expect(await data.margin(1)).toEqual([])
})

test("resolving an issue sends why, so a resolution naming a PR banks the sheriff's postmortem", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  await data.resolveIssue(31, "server/tmp/ gitignored in #327")
  expect(resolved).toEqual({ resolution: "server/tmp/ gitignored in #327" })
})

test("getting an issue fixed says which ticket owns it now and who has it", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  expect(await data.fixIssue(32)).toBe("issue #32 is ticket #400 now, routed to tertius")
})

test("a prompt is answered by its own id, never by a post on its thread", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  expect(await data.answer(9, "1")).toBe("answered")
  expect(answered).toEqual({ key: "1" })
})

test("a landing GitHub isn't merging: rebase it, or close and reland it, on its thread", async () => {
  process.env.TLON_URL = `http://127.0.0.1:${server.port}/api`
  const data = await import("../tui/data")
  expect(await data.rebaseLanding(44)).toContain("#44")
  expect(await data.relandLanding(44)).toContain("back to build")
})
