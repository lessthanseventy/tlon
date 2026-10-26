import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// esc from a ticket or an epic opened out of a list goes back to that list, not home: column →
// epic → ticket, then esc, esc walks back the way it came. Drives the real TUI against a stub server.
const tickets = [
  { id: 10, workspace_id: 1, project_id: null, title: "the big epic", priority: "normal", kind: "epic", done: 0, total: 1, next: null },
  { id: 11, workspace_id: 1, project_id: null, title: "the child ticket", priority: "normal", kind: "ticket", epic_id: 10 },
]
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-ticket-back-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-ticket-back-"))
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

test("esc from a ticket or epic returns to the list it was opened from", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  keys("t")
  await until("the tickets column", () => screen().includes("TICKETS ·"))
  keys("Space")
  await until("the epic", () => screen().includes("EPIC #10"))
  keys("Down", "Down", "Down", "Enter")
  await until("the child ticket", () => screen().includes("TICKET #11"))
  keys("Escape")
  await until("back on the epic", () => screen().includes("EPIC #10"))
  keys("Escape")
  await until("back on the column", () => screen().includes("TICKETS ·"))
  expect(screen()).not.toContain("EPIC #10")
}, 30_000)
