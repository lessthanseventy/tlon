import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// A thread card opens with its reply box focused: typing lands in it and Enter posts it; the first
// Esc leaves the box (the card's keys work again), the second goes back. Drives the real TUI
// against a stub server and reads what it posted.
let focusAt = 0
const posts: { path: string; body: unknown }[] = [], answers: { path: string; body: unknown }[] = []
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.endsWith("/messages")) { posts.push({ path, body: await req.json() }); return Response.json({ id: 2 }) }
    if (req.method === "POST" && path.includes("/office/prompts/")) { answers.push({ path, body: await req.json() }); return Response.json({ ok: true }) }
    if (path.endsWith("/office/focus")) return Response.json({ thread_id: 9, at: focusAt })
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/threads/10")) return Response.json({ messages: [], peek: null, window: null })
    if (path.endsWith("/office/threads/9")) return Response.json({ messages: [{ id: 1, author: "ada", body: "the sink is fixed", at: "2026-10-13T10:00:00Z", kind: "chat" }], peek: null, window: null })
    if (path.endsWith("/office")) return Response.json({
      roster: [], workspaces: [{ id: 1, name: "Toy" }],
      threads: [{ id: 9, title: "fix the sink", stage: null, awaiting: null, workspace_id: 1, lead: "ada", seat: "desk", standing: false },
        { id: 10, title: "the pipe question", stage: null, awaiting: null, workspace_id: 1, lead: "ada", seat: "desk", standing: false, prompt: { id: 77, summary: "replace the pipe?", options: [{ key: "yes", label: "yes" }, { key: "no", label: "no" }] } }],
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
const t0 = Date.now()
const until = async (what: string, ok: () => boolean) => {
  const deadline = Date.now() + 25_000
  let seen = ok()
  while (!seen && Date.now() < deadline) { await Bun.sleep(50); seen = ok() }
  if (!seen) throw new Error(`never saw ${what} after ${Date.now() - t0}ms; pane:\n${screen()}`)
}

test("a thread card opens with its reply box focused; esc leaves the box, esc again goes back", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "t")
  await until("the tickets column", () => screen().includes("TICKETS · "))
  tmux("send-keys", "-t", "0", "Right")
  await until("the doing column", () => screen().includes("DOING · "))
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

test("a thread with an open prompt opens with the box unfocused: 1 answers at once, as its card and in the reader", async () => {
  tmux("kill-server")
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "t")
  await until("the tickets column", () => screen().includes("TICKETS · "))
  tmux("send-keys", "-t", "0", "Right")
  await until("the doing column", () => screen().includes("DOING · "))
  tmux("send-keys", "-t", "0", "Down")
  await Bun.sleep(300)
  tmux("send-keys", "-t", "0", "Enter")
  await until("the prompt's card", () => screen().includes("THREAD #10"))
  tmux("send-keys", "-t", "0", "1")
  await until("the card's answer", () => answers.length === 1)
  tmux("send-keys", "-t", "0", "C-]")
  tmux("send-keys", "-t", "0", "/")
  await until("the finder", () => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "pipe question")
  await Bun.sleep(300)
  tmux("send-keys", "-t", "0", "Enter")
  await until("the reader on the prompt", () => screen().includes("replace the pipe?") && screen().includes("r or enter to write"))
  tmux("send-keys", "-t", "0", "1")
  await until("the reader's answer", () => answers.length === 2)
  expect(answers).toEqual([{ path: "/api/office/prompts/77", body: { key: "yes" } }, { path: "/api/office/prompts/77", body: { key: "yes" } }])
  expect(posts.length).toBe(1)
}, 40_000)

test("a thread another surface asks to show opens with the box unfocused: it never takes the keys unasked", async () => {
  tmux("kill-server")
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  await Bun.sleep(1500)
  focusAt = Date.now()
  await until("the reader on #9", () => screen().includes("the sink is fixed"))
  await Bun.sleep(300)
  expect(screen()).toContain("r or enter to write")
  expect(screen()).not.toContain("esc leave the box")
}, 40_000)
