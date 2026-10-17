import { afterAll, expect, test } from "bun:test"
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// A card whose name is already on the bench (an override: a pile entry brought back) is refused, and
// the refusal names what frees it — a pass rolls a fresh name; there is no lock to undo. Then ← → hires.
const dec = new TextDecoder()
let hired: { name: string } | null = null
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.endsWith("/workspaces/1/coworkers")) {
      hired = (await req.json()) as typeof hired
      return Response.json({ seat_id: 9, agent_id: 9, name: hired!.name, archetype: "builder" }, { status: 201 })
    }
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({
      roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }],
      bench: [{ workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null }],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-hall-taken-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-hall-taken-")), config = mkdtempSync(join(tmpdir(), "office-hall-taken-cfg-"))
mkdirSync(join(config, "tlon"), { recursive: true })
writeFileSync(join(config, "tlon/hall.json"), JSON.stringify({ seed: "hall:3", locks: {}, overrides: { name: "ada" }, pile: [] }))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  rmSync(config, { recursive: true, force: true })
  server.stop(true)
})
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const deadline = Date.now() + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}

test("a taken name is refused with a pass to free it, and a pass does", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' XDG_CONFIG_HOME='${config}' TLON_LOOKS='${config}/tlon/looks.json' TLON_SOULS='${config}/tlon/souls' TLON_HALL='${config}/tlon/hall.json' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "h")
  await until("the hall", () => screen().includes("HIRING HALL"))
  tmux("send-keys", "-t", "0", "Right")
  await until("the refusal", () => screen().includes("ada is already on the bench"))
  expect(screen()).toContain("ada is already on the bench — pass for a fresh name")
  expect(hired).toBeNull()
  tmux("send-keys", "-t", "0", "Left", "Right")
  await until("the hire", () => hired !== null)
  expect(hired!.name).not.toBe("ada")
}, 30_000)
