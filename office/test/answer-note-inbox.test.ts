import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// An ask lives on the needs inbox: its one-tap keys are the options' keys, and `"` opens the note box,
// whose first word is the option's number, key or label. Drives the real TUI against a stub server.
const answers: { path: string; body: unknown }[] = []
const need = {
  key: "ask:77", kind: "ask", level: "decide", thread_id: 10, workspace_id: 1, title: "replace the pipe?", text: "", at: new Date().toISOString(),
  options: [{ key: "y", label: "yes" }, { key: "n", label: "no" }], ref: 77, ask: "ada",
}
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.includes("/office/prompts/")) { answers.push({ path, body: await req.json() }); return Response.json({ ok: true }) }
    if (path.endsWith("/office/focus")) return Response.json({ thread_id: 0, at: 0 })
    if (path.endsWith("/office/needs")) return Response.json([need])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [] })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-note-inbox-${process.pid}-${Date.now()}`
const state = mkdtempSync(join(tmpdir(), "office-note-inbox-"))
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
const note = async (text: string, n: number) => {
  tmux("send-keys", "-t", "0", "\"")
  await until("the note box", () => screen().includes("answer with a note"))
  tmux("send-keys", "-t", "0", "-l", text)
  tmux("send-keys", "-t", "0", "Enter")
  await until("the answer", () => answers.length === n)
}

test("an inbox ask: the box takes a number, key or label and keeps the note as typed; a plain key sends the bare key", async () => {
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${join(import.meta.dir, "..")}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "i")
  await until("the ask's card", () => screen().includes("replace the pipe?") && screen().includes("answer with a note"))
  await note("2 the old one leaks", 1)
  await note("y  two  spaces", 2)
  await note("no because", 3)
  expect(answers.map((a) => a.body)).toEqual([{ key: "n the old one leaks" }, { key: "y two  spaces" }, { key: "n because" }])
  expect(answers.every((a) => a.path === "/api/office/prompts/77")).toBe(true)
  tmux("send-keys", "-t", "0", "y")
  await until("the plain answer", () => answers.length === 4)
  expect(answers[3]!.body).toEqual({ key: "y" })
}, 60_000)
