import { afterAll, expect, test } from "bun:test"
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { killServer } from "./kill-server"

// The hall's → on a live server hires through the operator API, then keeps the candidate's look
// and soul on the machine as the sandbox does.
const dec = new TextDecoder()
let hired: { name: string; archetype: string } | null = null
const posted: string[] = []
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.endsWith("/workspaces/1/coworkers")) {
      hired = (await req.json()) as typeof hired
      posted.push(hired!.name)
      return Response.json({ seat_id: 9, agent_id: 9, name: hired!.name, archetype: hired!.archetype }, { status: 201 })
    }
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }], bench: [{ workspace_id: 1, seat_id: 1, agent_id: 1, name: "funes", archetype: "builder", lead: false, model: null, ask: null }] })
    return new Response("no", { status: 404 })
  },
})
let socket = `tlon-office-hall-hire-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-hall-hire-")), config = mkdtempSync(join(tmpdir(), "office-hall-hire-cfg-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  killServer(socket)
  rmSync(state, { recursive: true, force: true })
  rmSync(config, { recursive: true, force: true })
  server.stop(true)
})
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const until = async (what: string, ok: () => boolean, deadline = performance.now() + 25_000) => {
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}

const office = join(import.meta.dir, "..")
const launch = (cfg: string) => tmux("new-session", "-d", "-x", "150", "-y", "50",
  `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' XDG_CONFIG_HOME='${cfg}' TLON_LOOKS='${cfg}/tlon/looks.json' TLON_SOULS='${cfg}/tlon/souls' TLON_HALL='${cfg}/tlon/hall.json' '${process.execPath}' tui/main.ts`)

test("→ in the hall hires on the server and keeps the look and soul", async () => {
  launch(config)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "h")
  await until("the hall", () => screen().includes("HIRING HALL"))
  tmux("send-keys", "-t", "0", "Right")
  await until("the hire said", () => hired !== null && screen().includes(`hired ${hired.name}`))
  expect(hired!.archetype).toBe("builder")
  expect(existsSync(join(config, "tlon/souls", `${hired!.name}.md`))).toBe(true)
  expect(Object.keys(JSON.parse(readFileSync(join(config, "tlon/looks.json"), "utf8")))).toContain(hired!.name)
}, 30_000)

test("→ on a name already on the bench is refused: nothing posted, nothing kept", async () => {
  killServer(socket)
  socket =`tlon-office-hall-taken-${process.pid}`
  const cfg = mkdtempSync(join(tmpdir(), "office-hall-taken-cfg-"))
  mkdirSync(join(cfg, "tlon"), { recursive: true })
  writeFileSync(join(cfg, "tlon/hall.json"), JSON.stringify({ seed: "hall:1", locks: {}, overrides: { name: "funes" }, pile: [] }))
  const before = posted.length
  try {
    launch(cfg)
    await until("the workspace in the header", () => screen().includes("Toy"))
    tmux("send-keys", "-t", "0", "h")
    await until("the hall", () => screen().includes("HIRING HALL"))
    tmux("send-keys", "-t", "0", "Right")
    await until("the refusal", () => screen().includes("funes is already on the bench"))
    expect(posted.length).toBe(before)
    expect(existsSync(join(cfg, "tlon/souls/funes.md"))).toBe(false)
    expect(existsSync(join(cfg, "tlon/looks.json"))).toBe(false)
  } finally { rmSync(cfg, { recursive: true, force: true }) }
}, 30_000)
