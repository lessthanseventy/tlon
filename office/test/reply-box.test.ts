import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// A thread card opens with its reply box focused: typing lands in it and Enter posts it; the first
// Esc leaves the box (the card's keys work again), the second goes back. Drives the real TUI
// against a stub server and reads what it posted.
const posts: { path: string; body: unknown }[] = []
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.endsWith("/messages")) { posts.push({ path, body: await req.json() }); return Response.json({ id: 2 }) }
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/threads/9")) return Response.json({ messages: [{ id: 1, author: "ada", body: "the sink is fixed", at: "2026-10-13T10:00:00Z", kind: "chat" }], peek: null, window: null })
    if (path.endsWith("/office")) return Response.json({
      roster: [], workspaces: [{ id: 1, name: "Toy" }],
      threads: [{ id: 9, title: "fix the sink", stage: null, awaiting: null, workspace_id: 1, lead: "ada", seat: "desk", standing: false }],
      bench: [{ workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null }],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-reply-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-reply-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const t0 = Date.now(), deadline = t0 + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what} after ${Date.now() - t0}ms; pane:\n${screen()}`)
}

test("a thread card opens with its reply box focused; esc leaves the box, esc again goes back", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "t")
  await until("the tickets column", () => screen().includes("TICKETS"))
  tmux("send-keys", "-t", "0", "Right")
  await until("the doing column", () => screen().includes("fix the sink"))
  tmux("send-keys", "-t", "0", "Enter")
  await until("the thread card", () => screen().includes("THREAD #9"))
  tmux("send-keys", "-t", "0", "-l", "on my way")
  await until("the typing in the reply box", () => screen().includes("on my way"))
  tmux("send-keys", "-t", "0", "Enter")
  await until("the reply posted", () => posts.length === 1)
  expect(posts).toEqual([{ path: "/api/threads/9/messages", body: { body: "on my way" } }])
  tmux("send-keys", "-t", "0", "Escape")
  await Bun.sleep(300)
  tmux("send-keys", "-t", "0", "t")
  await until("t looking over their shoulder", () => screen().includes("#9 has no live terminal"))
  expect(screen()).toContain("THREAD #9")
  tmux("send-keys", "-t", "0", "Escape")
  await until("the card left", () => !screen().includes("THREAD #9"))
  expect(posts.length).toBe(1)
}, 40_000)
