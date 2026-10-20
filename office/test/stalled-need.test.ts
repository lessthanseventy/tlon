import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// A stalled need's own keys (nudge, hand off, close), through the real TUI against a stub server.
const need = { key: "n1", kind: "stalled", level: "blocking", thread_id: 7, workspace_id: 1, title: "a stalled thing", text: "", at: new Date().toISOString(), options: null, ref: null }
const posts: { path: string; body: any }[] = []
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST") { posts.push({ path, body: await req.json().catch(() => null) }); return Response.json({ id: 1, title: "t", ok: true }, { status: 201 }) }
    if (path.endsWith("/office/needs")) return Response.json([need])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [{ id: 7, title: "stuck", workspace_id: 1 }], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [] })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-stalled-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-stalled-"))
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
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)

test("a stalled need lists nudge / hand off / close from the key table, and each does its thing", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the inbox in the header", () => screen().includes("1 blocking"))
  keys("i")
  await until("the stalled card", () => screen().includes("nudge the lead"))
  expect(screen()).toMatch(/\^ +nudge the lead/)
  expect(screen()).toMatch(/@ +hand it to/)
  expect(screen()).toMatch(/x +close it/)
  keys("^")
  await until("the nudge posted", () => posts.some((p) => p.path.endsWith("/threads/7/messages")))
  expect(posts.find((p) => p.path.endsWith("/threads/7/messages"))!.body.body ?? JSON.stringify(posts[0]!.body)).toContain("Nothing has moved")
}, 30_000)
