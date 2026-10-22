import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// The rack card (H) has one LANDING & CHECKS list: the waiters in the order the server sends them,
// the running train as one block (its gate, holding the check it runs, then its cars), who waits
// behind it, and a scheduled restart. Drives the real TUI against a stub server.
const at = new Date(Date.now() - 3 * 60_000).toISOString()
const car = (thread_id: number, title: string, pos: number) =>
  ({ thread_id, title, state: pos === 1 ? "landing" : "queued", train: { lead: 7, pos, size: 3, split: false }, gate: { pid: 4242, started_at: at } })
const health = {
  state: "ok", problems: [], version: "t", up_s: 60, db: true, jobs: true, failed_jobs: 0, tmux: true, disk_pct: 1, mem_pct: 1, load: 0.1,
  checks: { running: "#9 landing office-drive (pid 4242) in /w since 21:49:17", waiting: ["first waiter (pid 2) in /v since 21:50:00", "second waiter (pid 3) in /v since 21:50:01"] },
  merge_queue: [car(7, "the lead car", 1), car(8, "the middle car", 2), car(9, "office-drive", 3),
    { thread_id: 5, title: "PR #61 chat-ux", state: "queued", train: "solo", gate: null }],
}
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/health")) return Response.json(health)
    if (path.endsWith("/settings")) return Response.json({ knobs: [], restart_pending: true })
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [], health })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-rack-card-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-rack-card-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})
const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const deadline = performance.now() + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}

test("the rack lists landing & checks in one place, in order: a train is one block, its check not listed twice", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the room", () => screen().includes("Toy"))
  tmux("send-keys", "-t", "0", "H")
  await until("the rack", () => screen().includes("THE RACK"))
  await until("the list", () => screen().includes("LANDING & CHECKS"))
  const s = screen()
  expect(s).not.toContain("CHECKS QUEUE")
  expect(s).not.toContain("MERGE QUEUE")
  expect(s).not.toContain("one landing at a time")
  const pos = (t: string) => s.indexOf(t)
  expect([pos("first waiter"), pos("second waiter"), pos("🚃 train → main  gate running 3m · pid 4242"), pos("the lead car (lead)"),
    pos("the middle car"), pos("office-drive"), pos("PR #61 chat-ux (PR · lands solo)"), pos("a restart is scheduled")]
    .every((n, i, a) => n >= 0 && (i === 0 || n > a[i - 1]!))).toBe(true)
  expect(s.split("office-drive").length - 1).toBe(1)
  expect(s.split("train → main").length - 1).toBe(1)
}, 30_000)
