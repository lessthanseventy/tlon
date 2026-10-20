import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// The office's snapshot lands as soon as /office answers, whatever its other reads are doing: the
// inbox's (/office/needs) takes seconds on a real repo, and a finder opened before it returned
// listed nothing — release:smoke's drive found no thread for its title.
const dec = new TextDecoder()
const slow = Promise.withResolvers<void>()
// the first inbox read is never answered; the TUI gives up on it after its own timeout
let firstInboxGivenUp = false, inboxReads = 0
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) {
      if (inboxReads++ === 0) req.signal.addEventListener("abort", () => { firstInboxGivenUp = true })
      await slow.promise
      return Response.json([])
    }
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [{ id: 42, title: "the slow inbox", workspace_id: 1, stage: null, awaiting: null, lead: null }], workspaces: [{ id: 1, name: "Toy" }] })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-refresh-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-refresh-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  slow.resolve()
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const capture = () => tmux("capture-pane", "-p", "-t", "0")
const screen = () => dec.decode(capture().stdout)
// one budget for the whole test, under bun's own timeout, so a step that never lands throws its
// own message (which step, how long, the pane and tmux's complaint) instead of a bare timeout
const t0 = performance.now(), deadline = t0 + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) {
    const r = capture()
    throw new Error(`never saw ${what} after ${performance.now() - t0}ms (first inbox read given up: ${firstInboxGivenUp}); capture-pane exit ${r.exitCode}, stderr: ${dec.decode(r.stderr).trim() || "(none)"}; pane:
${dec.decode(r.stdout)}`)
  }
}

test("the finder lists the snapshot's threads while the inbox read is still out", async () => {
  const office = join(import.meta.dir, "..")
  // the running bun by path: a `bun` on PATH is a mise shim, which stops at its trust prompt in a checkout the service's env hasn't trusted
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  // the snapshot is in: its workspace names the header
  await until("the workspace in the header", () => screen().includes("Toy"))
  expect(screen()).toContain("Toy")
  tmux("send-keys", "-t", "0", "/")
  await until("FIND after /", () => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "slow inbox")
  await until("#42 in the finder", () => screen().includes("#42 the slow inbox"))
  expect(screen()).toContain("#42 the slow inbox")
  // listed while that read was still out, not after the TUI gave up on it
  expect(firstInboxGivenUp).toBe(false)
}, 30_000)
