import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Uqbar's entry (U) marks its footnotes ¹ ² …: the digit under a mark opens that footnote, and the
// actions pane says so. Drives the real TUI against a stub server with two footnotes (the inbox, the rack).
const need = { key: "n1", kind: "stalled", level: "blocking", thread_id: null, workspace_id: 1, title: "a stalled thing", text: "", at: new Date().toISOString(), options: null, ref: null }
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([need])
    if (path.endsWith("/office")) return Response.json({
      roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [],
      health: { state: "warn", problems: ["the disk is full"], checks: { running: null, waiting: [] }, merge_queue: [] },
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-entry-keys-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-entry-keys-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const deadline = performance.now() + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)

test("a digit opens its footnote, and the pane lists it", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the phone in the header", () => screen().includes("1 waiting on you"))
  keys("U")
  await until("the entry's footnotes", () => screen().includes("FOOTNOTES"))
  expect(screen()).toMatch(/2 +footnote ² — the rack/)
  keys("2")
  await until("the rack", () => screen().includes("THE RACK"))
  keys("Escape")
  keys("U")
  await until("the entry again", () => screen().includes("FOOTNOTES"))
  keys("1")
  await until("the inbox", () => screen().includes("DECIDE · 1 of 1"))
}, 30_000)
