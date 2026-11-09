import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { started, TUI_TEST } from "./started"
import { waitFor } from "./wait-for"

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
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)

test("enter folds a group open in place; a ticket opens; o opens the group's card", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks OFFICE_NO_ANIMATE=1 XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await started(tmux, "the workspace in the header", () => screen().includes("Toy"))
  keys("t")
  await waitFor(screen, "TICKETS ·", "the tickets column")
  expect(screen()).not.toContain("the child ticket")

  keys("Enter")
  await waitFor(screen, "the child ticket", "the epic's children under it")
  expect(screen()).toContain("the started child")
  expect(screen()).toContain("⚙ on #40")
  expect(screen()).not.toContain("EPIC #10")

  keys("Enter")
  await waitFor(screen, () => !screen().includes("the child ticket"), "the children folded away")

  keys("Enter")
  await waitFor(screen, "the child ticket", "the children again")
  keys("Down", "Enter")
  await waitFor(screen, "TICKET #11", "the child ticket")
  keys("Escape")
  await waitFor(screen, "TICKETS ·", "back on the column")

  keys("Up", "Space")
  await waitFor(screen, "EPIC #10", "the epic's card")
}, TUI_TEST)

test("the tree's card does not claim a who sort: tickets carry no owner", async () => {
  keys("C-]")
  await waitFor(screen, () => !screen().includes("EPIC #10") && !screen().includes("TICKETS ·"), "the room")
  keys("t")
  await waitFor(screen, "TICKETS ·", "the tickets column")
  keys("s")
  await waitFor(screen, "by title", "the title sort")
  keys("s")
  await waitFor(screen, () => !screen().includes("by title"), "the sort moved on")
  expect(screen()).not.toContain("by who")
}, TUI_TEST)
