import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// The first motion onto a margin note both lights it and shows its tip: one motion event, no
// second one at the same cell needed. Drives the real TUI against a stub server with one note.
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/margin/1")) return Response.json([{ id: 1, author: "uqbar", body: "see #42 again", at: Math.floor(Date.now() / 1000) }])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [] })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-margin-tip-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-margin-tip-"))
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

test("one motion onto a note shows its tip", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "200", "-y", "60",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks OFFICE_WIDE=1 XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the note in the margin", () => screen().includes("#42"))
  const lines = screen().split("\n"), row = lines.findIndex((l) => l.includes("#42")), col = lines[row]!.indexOf("#42")
  tmux("send-keys", "-t", "0", "-l", `\x1b[<35;${col + 2};${row + 1}M`)
  await Bun.sleep(600)
  expect(screen()).toContain("enter opens #42")
}, 30_000)
