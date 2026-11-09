import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { started, TUI_TEST } from "./started"
import { waitFor } from "./wait-for"

// e → "draw a new one (reroll)" throws away the persona's hand edits, so it asks first: n changes
// nothing, y rerolls, and says so while the model call runs. Drives the real TUI against a stub
// server that holds the reroll's answer until the test lets it go, and reads what it posted.
const persona = { seed: 7, source: "model", voice: "dry", backstory: "Grew up above a clockmaker's.", quirks: { desk_object: "a mug", hobby: "chess", catchphrase: "Noted.", pet_peeve: "tabs" } }
const posts: string[] = []
let answer = () => {}
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.endsWith("/persona")) { posts.push(path); await new Promise<void>((r) => { answer = r }); return Response.json({ seed: 9 }) }
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({
      roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }],
      bench: [{ workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null, persona }],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-reroll-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-reroll-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)

test("e then reroll asks first: n changes nothing, y rerolls", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks OFFICE_NO_ANIMATE=1 XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await started(tmux, "the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "/")
  await waitFor(screen, "FIND", "FIND")
  tmux("send-keys", "-t", "0", "-l", "ada")
  await waitFor(screen, "coworker ada", "ada in the finder")
  tmux("send-keys", "-t", "0", "enter")
  await waitFor(screen, (s) => !s.includes("FIND"), "the finder closed")
  tmux("send-keys", "-t", "0", "e")
  await waitFor(screen, "ADA'S PERSONA", "the persona picker")
  tmux("send-keys", "-t", "0", "enter")
  await waitFor(screen, () => screen().includes("reroll") && screen().includes("(y/n)"), "the reroll ask")
  tmux("send-keys", "-t", "0", "n")
  await waitFor(screen, (s) => !s.includes("(y/n)"), "the ask answered")
  expect(screen()).not.toContain("(y/n)")
  expect(posts).toEqual([])
  tmux("send-keys", "-t", "0", "e")
  await waitFor(screen, "ADA'S PERSONA", "the persona picker again")
  tmux("send-keys", "-t", "0", "enter")
  await waitFor(screen, "(y/n)", "the reroll ask again")
  tmux("send-keys", "-t", "0", "y")
  await waitFor(screen, () => posts.length === 1, "the reroll posted")
  expect(posts).toEqual(["/api/workspaces/1/coworkers/5/persona"])
  await waitFor(screen, "drawing a new one", "the wait said")
  answer()
}, TUI_TEST)
