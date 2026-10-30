import { afterAll, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { started, TUI_TEST } from "./started"

// K moves a ticket among its siblings, and the cursor goes with it: here the mover swaps past an
// open epic, and the cursor must land on the mover, not on the row the epic's child used to sit on.
// Drives the real TUI against a stub server that keeps the tickets' order and answers the reorder.
let tickets = [
  { id: 20, workspace_id: 1, project_id: null, title: "the top one", priority: "normal", kind: "ticket", status: "todo", sort: 1 },
  { id: 10, workspace_id: 1, project_id: null, title: "the epic", priority: "normal", kind: "epic", done: 0, total: 1, next: null, status: "todo", sort: 2 },
  { id: 11, workspace_id: 1, project_id: null, title: "the epic's child", priority: "normal", kind: "ticket", epic_id: 10, status: "todo", sort: 3 },
  { id: 21, workspace_id: 1, project_id: null, title: "the mover", priority: "normal", kind: "ticket", status: "todo", sort: 4 },
]
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const url = new URL(req.url)
    const path = url.pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [...tickets].sort((a, b) => a.sort - b.sort) })
    const reorder = path.match(/\/tickets\/(\d+)\/reorder$/)
    if (reorder && req.method === "POST") {
      const body = (await req.json()) as { direction: "up" | "down" }
      const mover = tickets.find((t) => t.id === Number(reorder[1]))!
      // the server's rule: a ticket's neighbour is a sibling, the same epic (none for top-level)
      const siblings = tickets.filter((t) => t.id !== mover.id && (t as { epic_id?: number }).epic_id === (mover as { epic_id?: number }).epic_id)
      const above = siblings.filter((t) => t.sort < mover.sort).sort((a, b) => b.sort - a.sort)[0]
      const below = siblings.filter((t) => t.sort > mover.sort).sort((a, b) => a.sort - b.sort)[0]
      const other = body.direction === "up" ? above : below
      if (other) [mover.sort, other.sort] = [other.sort, mover.sort]
      return Response.json({ ticket: mover.id, moved: other !== undefined })
    }
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-tree-reorder-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-tree-reorder-"))
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
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)

test("K moves a ticket among its siblings and the cursor stays on it, past an open epic", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await started(tmux, "the workspace in the header", () => screen().includes("Toy"))
  keys("t")
  await until("the tickets column", () => screen().includes("TICKETS ·"))

  // open the epic: its child shows under it, and the mover sits below the child
  keys("Enter")
  await until("the epic's child", () => screen().includes("the epic's child"))

  // the epic's child is its epic's only child: K has no sibling to swap with, and says so instead of "moved"
  keys("Down", "K")
  await until("the nothing-to-swap report", () => screen().includes("#11 has no sibling to swap with"))
  // the cursor marker is ▸: walk down until it sits on the mover's row
  const onMover = () => screen().split("\n").some((l) => l.includes("▸") && l.includes("#21 the mover"))
  for (let i = 0; i < 6 && !onMover(); i++) {
    keys("Down")
    await Bun.sleep(150)
  }
  await until("the cursor on the mover", onMover)

  // the mover swaps with the epic (a top-level sibling), which sits open above it: the cursor
  // stays on the mover's row, not on the row above where the mover used to sit
  keys("K")
  await until("the move reported", () => screen().includes("#21 moved up"))
  await until("the cursor still on the mover after the move", () => {
    const s = screen()
    return s.includes("the mover") && s.split("\n").some((l) => l.includes("▸") && l.includes("#21 the mover"))
  })

  keys("Enter")
  await until("the mover's ticket card", () => screen().includes("TICKET #21"))
}, TUI_TEST)
