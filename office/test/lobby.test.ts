import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Ctrl-] is the lobby — the room with nothing open over it — from a card, a focused reply box, the
// finder and the reader. Drives the real TUI against a stub server; it never posts.
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
const socket = `tlon-office-lobby-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-lobby-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const t0 = Date.now()
const until = async (what: string, ok: () => boolean) => {
  const deadline = Date.now() + 25_000
  let seen = ok()
  while (!seen && Date.now() < deadline) { await Bun.sleep(50); seen = ok() }
  if (!seen) throw new Error(`never saw ${what} after ${Date.now() - t0}ms; pane:\n${screen()}`)
}

const LOBBY = "nothing waits on you"
const lobby = async (from: string) => {
  tmux("send-keys", "-t", "0", "C-]")
  await until(`the lobby from ${from}`, () => screen().includes(LOBBY) && !screen().includes("THREAD #9") && !screen().includes("FIND"))
}
const card = async () => {
  tmux("send-keys", "-t", "0", "t")
  await until("the tickets column", () => screen().includes("TICKETS · "))
  tmux("send-keys", "-t", "0", "Right")
  await until("the doing column", () => screen().includes("DOING · "))
  tmux("send-keys", "-t", "0", "Enter")
  await until("the thread card", () => screen().includes("THREAD #9"))
}

test("ctrl-] goes to the lobby from a reply box, a card, the finder and the reader", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the lobby", () => screen().includes(LOBBY))
  await card()
  tmux("send-keys", "-t", "0", "-l", "half a thought")
  await until("the typing in the box", () => screen().includes("half a thought"))
  await lobby("the reply box")
  await card()
  tmux("send-keys", "-t", "0", "Escape")
  await Bun.sleep(300)
  await lobby("the card")
  tmux("send-keys", "-t", "0", "/")
  await until("the finder", () => screen().includes("FIND"))
  await lobby("the finder")
  tmux("send-keys", "-t", "0", "/")
  await until("the finder", () => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "#9")
  await until("the thread in the finder", () => screen().includes("fix the sink"))
  tmux("send-keys", "-t", "0", "Enter")
  await until("the reader", () => screen().includes("the sink is fixed") && !screen().includes(LOBBY))
  await lobby("the reader")
  expect(posts).toEqual([])
}, 40_000)

test("ctrl-] keeps what you were writing: the card's box, the reader's and an input's, there when you come back", async () => {
  await card()
  await until("the card's draft kept", () => screen().includes("half a thought"))
  await lobby("the card")
  tmux("send-keys", "-t", "0", "/")
  await until("the finder", () => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "#9")
  await until("the thread in the finder", () => screen().includes("fix the sink"))
  tmux("send-keys", "-t", "0", "Enter")
  await until("the reader with the card's draft", () => screen().includes("the sink is fixed") && screen().includes("half a thought"))
  tmux("send-keys", "-t", "0", "-l", " and more")
  await until("the reader's typing", () => screen().includes("half a thought and more"))
  await lobby("the reader")
  await card()
  await until("the reader's draft on the card", () => screen().includes("half a thought and more"))
  await lobby("the card")
  tmux("send-keys", "-t", "0", "'")
  await until("the talk input", () => screen().includes("say to the office"))
  tmux("send-keys", "-t", "0", "-l", "lunch at noon")
  await until("the input's typing", () => screen().includes("lunch at noon"))
  tmux("send-keys", "-t", "0", "C-]")
  await until("the lobby from the input", () => screen().includes(LOBBY) && !screen().includes("say to the office"))
  tmux("send-keys", "-t", "0", "'")
  await until("the input's draft back", () => screen().includes("say to the office") && screen().includes("lunch at noon"))
  tmux("send-keys", "-t", "0", "C-]")
  expect(posts).toEqual([])
}, 40_000)
