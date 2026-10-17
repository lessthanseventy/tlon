import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Scharlach's ledger ticks every red thread once, not just the five the triage card shows: seven red
// builds of ada's are seven demerits. Drives the real TUI against a stub server and reads his card.
const reds = [1, 2, 3, 4, 5, 6, 7].map((i) => ({ thread_id: 100 + i, title: `red ${i}`, text: "mix test" }))
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/triage/1")) return Response.json({
      blockers: { shown: [], more: 0 }, unled: { shown: [], more: 0 }, count: 7,
      failed_checks: { shown: reds.slice(0, 5), more: 2, ids: reds.map((r) => r.thread_id) },
    })
    if (path.endsWith("/office")) return Response.json({
      roster: [], workspaces: [{ id: 1, name: "Toy" }], tickets: [], triage: { "1": 7 },
      threads: reds.map((r) => ({ id: r.thread_id, title: r.title, stage: null, awaiting: null, workspace_id: 1, lead: "ada" })),
      bench: [
        { workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null },
        { workspace_id: 1, seat_id: 2, agent_id: 6, name: "scharlach", archetype: "sheriff", lead: false, model: null, ask: null },
      ],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-ledger-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-ledger-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const deadline = Date.now() + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)

test("seven reds past the triage's cap are seven demerits", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  keys("/")
  await until("FIND", () => screen().includes("FIND"))
  keys("-l", "scharlach")
  await until("scharlach in the finder", () => screen().includes("coworker scharlach"))
  keys("Enter")
  await until("his ledger", () => screen().includes("demerits:"))
  await Bun.sleep(300)
  expect(screen()).toMatch(/ada 7\b/)
}, 30_000)
