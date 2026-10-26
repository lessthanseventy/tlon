import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// the TICKETS column is a tree: enter on a group opens it in place (its children indent under it,
// an in-flight child names its thread), enter again folds it, enter on a ticket opens the ticket,
// and `o` opens the group's own card. Drives the real TUI against a stub server.
const tickets = [
  { id: 10, workspace_id: 1, project_id: null, title: "the big epic", priority: "normal", kind: "epic", done: 0, total: 2, next: null },
  { id: 11, workspace_id: 1, project_id: null, title: "the child ticket", priority: "normal", kind: "ticket", epic_id: 10, status: "todo" },
  { id: 12, workspace_id: 1, project_id: null, title: "the started child", priority: "normal", kind: "ticket", epic_id: 10, status: "doing", thread_id: 40 },
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
const socket = `tlon-office-column-tree-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-column-tree-"))
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

test("enter folds a group open in place; a ticket opens; o opens the group's card", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  keys("t")
  await until("the tickets column", () => screen().includes("TICKETS ·"))
  expect(screen()).not.toContain("the child ticket")

  keys("Enter")
  await until("the epic's children under it", () => screen().includes("the child ticket"))
  expect(screen()).toContain("the started child")
  expect(screen()).toContain("⚙ on #40")
  expect(screen()).not.toContain("EPIC #10")

  keys("Enter")
  await until("the children folded away", () => !screen().includes("the child ticket"))

  keys("Enter")
  await until("the children again", () => screen().includes("the child ticket"))
  keys("Down", "Enter")
  await until("the child ticket", () => screen().includes("TICKET #11"))
  keys("Escape")
  await until("back on the column", () => screen().includes("TICKETS ·"))

  keys("Up", "Space")
  await until("the epic's card", () => screen().includes("EPIC #10"))
}, 30_000)

test("the tree's card does not claim a who sort: tickets carry no owner", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  keys("t")
  await until("the tickets column", () => screen().includes("TICKETS ·"))
  keys("s")
  await until("the title sort", () => screen().includes("by title"))
  keys("s")
  await until("the sort moved on", () => !screen().includes("by title"))
  expect(screen()).not.toContain("by who")
}, 30_000)
