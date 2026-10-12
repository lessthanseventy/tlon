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

const until = async (ok: () => boolean) => { for (let i = 0; i < 300 && !ok(); i++) await Bun.sleep(50) }
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)

test("the finder lists the snapshot's threads while the inbox read is still out", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' bun tui/main.ts`)
  // the snapshot is in: its workspace names the header
  await until(() => screen().includes("Toy"))
  expect(screen()).toContain("Toy")
  tmux("send-keys", "-t", "0", "/")
  await until(() => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "slow inbox")
  await until(() => screen().includes("#42 the slow inbox"))
  expect(screen()).toContain("#42 the slow inbox")
  // listed while that read was still out, not after the TUI gave up on it
  expect(firstInboxGivenUp).toBe(false)
}, 30_000)
