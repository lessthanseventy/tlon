import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// The cast editor (the god view) drives the real TUI against a stub server with two seats on the
// bench, its config dir a throwaway one so nothing reaches the operator's files.
const persona = { seed: 7, source: "model", voice: "dry", backstory: "Grew up above a clockmaker's.", quirks: { desk_object: "a mug", hobby: "chess", catchphrase: "Noted.", pet_peeve: "tabs" } }
const bench = [
  { workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null, persona },
  { workspace_id: 1, seat_id: 2, agent_id: 6, name: "bo", archetype: "reviewer", lead: false, model: null, ask: null, persona: null },
]
// every write the TUI sends, as "METHOD /path"
const writes: string[] = []
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (req.method !== "GET") { writes.push(`${req.method} ${path}`); return Response.json({ seed: 9 }) }
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-cast-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-cast-")), config = mkdtempSync(join(tmpdir(), "office-cast-config-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  rmSync(config, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const until = async (what: string, ok: () => boolean) => {
  const t0 = performance.now(), deadline = t0 + 15_000
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what} after ${performance.now() - t0}ms; pane:\n${screen()}`)
}

test("` opens the cast: a row per seat, } the office tab, esc home", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' XDG_CONFIG_HOME='${config}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "-l", "`")
  await until("the cast", () => screen().includes("THE CAST"))
  expect(screen()).toContain("ada")
  expect(screen()).toContain("bo")
  expect(screen()).toContain("unset")
  tmux("send-keys", "-t", "0", "-l", "}")
  await until("the office tab", () => screen().includes("WACKINESS"))
  tmux("send-keys", "-t", "0", "escape")
  await until("home again", () => !screen().includes("WACKINESS") && !screen().includes("THE CAST"))
}, 40_000)

const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)
const field = async (name: string) => {
  for (let i = 0; i < 8 && !screen().includes(`THE CAST · people · ${name}`); i++) { keys("right"); await Bun.sleep(150) }
  await until(`the ${name} field lit`, () => screen().includes(`THE CAST · people · ${name}`))
}

test("⏎ on voice is the persona picker: its reroll asks, y posts it", async () => {
  keys("-l", "`")
  await until("the cast", () => screen().includes("THE CAST · people"))
  await field("voice")
  keys("enter")
  await until("the persona picker", () => screen().includes("ADA'S PERSONA"))
  keys("enter")
  await until("the reroll ask", () => screen().includes("(y/n)"))
  keys("y")
  await until("the reroll posted", () => writes.includes("POST /api/workspaces/1/coworkers/5/persona"))
}, 40_000)

test("⏎ on model is the model picker", async () => {
  await field("model")
  keys("enter")
  await until("the model picker", () => screen().includes("ADA'S MODEL"))
  keys("escape")
}, 40_000)

test("- lets the lit seat go, after asking: n sends nothing, y the DELETE", async () => {
  await until("the cast", () => screen().includes("THE CAST · people"))
  writes.length = 0
  keys("-")
  await until("the unseat ask", () => screen().includes("let ada go") && screen().includes("(y/n)"))
  keys("n")
  await Bun.sleep(400)
  expect(writes).toEqual([])
  keys("-")
  await until("the unseat ask again", () => screen().includes("(y/n)"))
  keys("y")
  await until("the DELETE", () => writes.includes("DELETE /api/seats/1"))
}, 40_000)
