import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { started, TUI_TEST } from "./started"
import { waitFor } from "./wait-for"

// Ctrl-] is the room — the room with nothing open over it — from a card, a focused reply box, the
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
const socket = `tlon-office-room-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-room-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)

const ROOM = "nothing waits on you"
const room = async (from: string) => {
  tmux("send-keys", "-t", "0", "C-]")
  await waitFor(screen, () => screen().includes(ROOM) && !screen().includes("THREAD #9") && !screen().includes("FIND"), `the room from ${from}`)
}
const card = async () => {
  tmux("send-keys", "-t", "0", "t")
  await waitFor(screen, "TICKETS · ", "the tickets column")
  tmux("send-keys", "-t", "0", "Right", "Right", "Right")
  await waitFor(screen, "BUILD · ", "the build column")
  tmux("send-keys", "-t", "0", "Enter")
  await waitFor(screen, "THREAD #9", "the thread card")
}

test("ctrl-] goes to the room from a reply box, a card, the finder and the reader", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks OFFICE_NO_ANIMATE=1 XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await started(tmux, "the room", () => screen().includes(ROOM))
  await card()
  tmux("send-keys", "-t", "0", "-l", "half a thought")
  await waitFor(screen, "half a thought", "the typing in the box")
  await room("the reply box")
  await card()
  tmux("send-keys", "-t", "0", "Escape")
  await waitFor(screen, (s) => !s.includes("esc leave the box"), "the box left")
  await room("the card")
  tmux("send-keys", "-t", "0", "/")
  await waitFor(screen, "FIND", "the finder")
  await room("the finder")
  tmux("send-keys", "-t", "0", "/")
  await waitFor(screen, "FIND", "the finder")
  tmux("send-keys", "-t", "0", "-l", "#9")
  await waitFor(screen, "fix the sink", "the thread in the finder")
  tmux("send-keys", "-t", "0", "Enter")
  await waitFor(screen, () => screen().includes("the sink is fixed") && !screen().includes(ROOM), "the reader")
  await room("the reader")
  expect(posts).toEqual([])
}, TUI_TEST)

test("ctrl-] keeps what you were writing: the card's box, the reader's and an input's, there when you come back", async () => {
  await card()
  await waitFor(screen, "half a thought", "the card's draft kept")
  await room("the card")
  tmux("send-keys", "-t", "0", "/")
  await waitFor(screen, "FIND", "the finder")
  tmux("send-keys", "-t", "0", "-l", "#9")
  await waitFor(screen, "fix the sink", "the thread in the finder")
  tmux("send-keys", "-t", "0", "Enter")
  await waitFor(screen, () => screen().includes("the sink is fixed") && screen().includes("half a thought"), "the reader with the card's draft")
  tmux("send-keys", "-t", "0", "-l", " and more")
  await waitFor(screen, "half a thought and more", "the reader's typing")
  await room("the reader")
  await card()
  await waitFor(screen, "half a thought and more", "the reader's draft on the card")
  await room("the card")
  tmux("send-keys", "-t", "0", "'")
  await waitFor(screen, "say to the office", "the talk input")
  tmux("send-keys", "-t", "0", "-l", "lunch at noon")
  await waitFor(screen, "lunch at noon", "the input's typing")
  tmux("send-keys", "-t", "0", "C-]")
  await waitFor(screen, () => screen().includes(ROOM) && !screen().includes("say to the office"), "the room from the input")
  tmux("send-keys", "-t", "0", "'")
  await waitFor(screen, () => screen().includes("say to the office") && screen().includes("lunch at noon"), "the input's draft back")
  tmux("send-keys", "-t", "0", "C-]")
  expect(posts).toEqual([])
}, 40_000)
