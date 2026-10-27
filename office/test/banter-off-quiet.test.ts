import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// With the office dial's banter off, chatter() asks the server for nothing it writes lazily with model
// tokens (banter, pets, corkboard, talk). Drives the real TUI against a stub server and reads the paths it hit.
const hits: string[] = []
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    hits.push(path)
    if (path.endsWith("/office/focus")) return Response.json({ thread_id: 0, at: 0 })
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.includes("/office/suggestions/")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({
      roster: [], workspaces: [{ id: 1, name: "Toy" }], threads: [],
      bench: [{ workspace_id: 1, seat_id: 1, agent_id: 5, name: "ada", archetype: "builder", lead: false, model: null, ask: null }],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-quiet-${process.pid}-${Date.now()}`
const state = mkdtempSync(join(tmpdir(), "office-quiet-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

test("banter off: chatter() makes no banter, pets, corkboard or talk call", async () => {
  const dial = join(state, "office.json")
  writeFileSync(dial, JSON.stringify({ mode: "office", preset: "casual", overrides: { banter: false } }))
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${join(import.meta.dir, "..")}' && TLON_URL='http://127.0.0.1:${server.port}' TLON_OFFICE='${dial}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  const deadline = performance.now() + 25_000
  while (!hits.some((p) => p.includes("/office/suggestions/")) && performance.now() < deadline) await Bun.sleep(50)
  expect(hits.some((p) => p.includes("/office/suggestions/"))).toBe(true) // chatter() ran to the end
  expect(hits.filter((p) => /\/office\/(banter|pets|corkboard|talk)\b/.test(p))).toEqual([])
}, 40_000)
