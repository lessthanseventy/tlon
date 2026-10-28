import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// `R` on an out-of-date office reloads the real TUI, run in a tmux of the test's own against a stub
// server whose office revision moves on: afterwards one office runs, in the same process
let rev = "aaa111"
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], revs: { office: rev } })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-reload-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-reload-"))
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
  const deadline = performance.now() + 15_000
  let seen = ok()
  while (!seen && performance.now() < deadline) { await Bun.sleep(50); seen = ok() }
  if (!seen) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
/** the bun processes under the pane: the offices running in it */
const offices = () => {
  const root = Number(dec.decode(tmux("display", "-p", "-t", "0", "#{pane_pid}").stdout).trim())
  const rows = dec.decode(Bun.spawnSync(["ps", "-e", "-o", "pid=,ppid=,comm="]).stdout).trim().split("\n").map((l) => l.trim().split(/\s+/))
  const under = new Set([root])
  for (let grew = true; grew;) {
    grew = false
    for (const [pid, ppid] of rows) if (under.has(Number(ppid)) && !under.has(Number(pid))) { under.add(Number(pid)); grew = true }
  }
  return rows.filter(([pid, , comm]) => under.has(Number(pid)) && comm === "bun").map(([pid]) => Number(pid))
}

test("R reloads in place: one office, the same process", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' XDG_CONFIG_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
  rev = "bbb222"
  await until("the reload offer", () => screen().includes("R reloads"))
  const before = offices()
  expect(before).toHaveLength(1)
  tmux("send-keys", "-t", "0", "-l", "R")
  await until("the reloaded office, on the new revision", () => screen().includes("Toy") && !screen().includes("R reloads"))
  expect(offices()).toEqual(before)
}, 40_000)
