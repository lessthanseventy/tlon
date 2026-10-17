import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// E → "draw a new one (reroll)" throws away the persona's hand edits, so it asks first: n changes
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
const t0 = Date.now(), deadline = t0 + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what} after ${Date.now() - t0}ms; pane:\n${screen()}`)
}
const settle = () => Bun.sleep(400)

test("E then reroll asks first: n changes nothing, y rerolls", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "/")
  await until("FIND", () => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "ada")
  await until("ada in the finder", () => screen().includes("coworker ada"))
  tmux("send-keys", "-t", "0", "enter")
  await settle()
  tmux("send-keys", "-t", "0", "E")
  await until("the persona picker", () => screen().includes("ADA'S PERSONA"))
  tmux("send-keys", "-t", "0", "enter")
  await until("the reroll ask", () => screen().includes("reroll") && screen().includes("(y/n)"))
  tmux("send-keys", "-t", "0", "n")
  await settle()
  expect(screen()).not.toContain("(y/n)")
  expect(posts).toEqual([])
  tmux("send-keys", "-t", "0", "E")
  await until("the persona picker again", () => screen().includes("ADA'S PERSONA"))
  tmux("send-keys", "-t", "0", "enter")
  await until("the reroll ask again", () => screen().includes("(y/n)"))
  tmux("send-keys", "-t", "0", "y")
  await until("the reroll posted", () => posts.length === 1)
  expect(posts).toEqual(["/api/workspaces/1/coworkers/5/persona"])
  await until("the wait said", () => screen().includes("drawing a new one"))
  answer()
}, 40_000)
