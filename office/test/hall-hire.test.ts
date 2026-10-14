import { afterAll, expect, test } from "bun:test"
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// The hall's → on a live server hires through the operator API, then keeps the candidate's look
// and soul on the machine as the sandbox does.
const dec = new TextDecoder()
let hired: { name: string; archetype: string } | null = null
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST" && path.endsWith("/workspaces/1/coworkers")) {
      hired = (await req.json()) as typeof hired
      return Response.json({ seat_id: 9, agent_id: 9, name: hired!.name, archetype: hired!.archetype }, { status: 201 })
    }
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }], bench: [] })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-hall-hire-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-hall-hire-")), config = mkdtempSync(join(tmpdir(), "office-hall-hire-cfg-"))
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

test("→ in the hall hires on the server and keeps the look and soul", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' XDG_CONFIG_HOME='${config}' TLON_LOOKS='${config}/tlon/looks.json' TLON_SOULS='${config}/tlon/souls' TLON_HALL='${config}/tlon/hall.json' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "h")
  await until("the hall", () => screen().includes("HIRING HALL"))
  tmux("send-keys", "-t", "0", "Right")
  await until("the hire said", () => hired !== null && screen().includes(`hired ${hired.name}`))
  expect(hired!.archetype).toBe("builder")
  expect(existsSync(join(config, "tlon/souls", `${hired!.name}.md`))).toBe(true)
  expect(Object.keys(JSON.parse(readFileSync(join(config, "tlon/looks.json"), "utf8")))).toContain(hired!.name)
}, 30_000)
