import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// An ask is answered by one tap (1–9), or with a note: `"` opens a one-line box, "<number> <note>"
// and Enter send "<key> <note>" through the same POST /api/office/prompts/:id. Drives the real TUI
// against a stub server and reads what it was sent.
const answers: { path: string; body: unknown }[] = []
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.includes("/office/prompts/")) { answers.push({ path, body: await req.json() }); return Response.json({ ok: true }) }
    if (path.endsWith("/office/focus")) return Response.json({ thread_id: 0, at: 0 })
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/threads/10")) return Response.json({ messages: [], peek: null, window: null })
    if (path.endsWith("/office")) return Response.json({
      roster: [], workspaces: [{ id: 1, name: "Toy" }],
      threads: [{ id: 10, title: "the pipe question", stage: null, awaiting: null, workspace_id: 1, lead: "ada", seat: "desk", standing: false, prompt: { id: 77, summary: "replace the pipe?", options: [{ key: "yes", label: "yes" }, { key: "no", label: "no" }] } }],
      bench: [{ workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null }],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-note-${process.pid}-${Date.now()}`
const state = mkdtempSync(join(tmpdir(), "office-note-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})
const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const until = async (what: string, ok: () => boolean) => {
  const deadline = performance.now() + 25_000
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}

test("\" answers an ask with a note: the body is \"<key> <note>\"; a plain 1 still sends the bare key", async () => {
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${join(import.meta.dir, "..")}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "t")
  await until("the tickets column", () => screen().includes("TICKETS · "))
  tmux("send-keys", "-t", "0", "Right", "Right", "Right")
  await until("the build column", () => screen().includes("BUILD · "))
  tmux("send-keys", "-t", "0", "Enter")
  await until("the prompt's card", () => screen().includes("THREAD #10"))
  tmux("send-keys", "-t", "0", "\"")
  await until("the note box", () => screen().includes("answer with a note"))
  tmux("send-keys", "-t", "0", "-l", "2 the old one leaks")
  tmux("send-keys", "-t", "0", "Enter")
  await until("the answer with its note", () => answers.length === 1)
  expect(answers).toEqual([{ path: "/api/office/prompts/77", body: { key: "no the old one leaks" } }])
  tmux("send-keys", "-t", "0", "1")
  await until("the plain answer", () => answers.length === 2)
  expect(answers[1]).toEqual({ path: "/api/office/prompts/77", body: { key: "yes" } })
}, 40_000)
