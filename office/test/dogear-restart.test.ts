import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// A post whose aeroplane Argos caught stays dog-eared across a TUI restart. Run one: four fresh uqbar
// posts fly, the 4th is caught, its reader shows 🐾. Run two, same state dir: the paw is still there.
const at = (i: number) => `2026-10-12T10:0${i}:00.000000Z`
const posts = [1, 2, 3, 4].map((i) => ({ kind: "message", at: at(i), thread_id: 7, who: "uqbar", text: `post ${i}` }))
const older = { kind: "work_landed", at: at(0), thread_id: 7, who: "tlon", text: "history" }
let feeds = 0
const server = Bun.serve({
  port: 0,
  fetch: (req) => {
    const path = new URL(req.url).pathname
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office/activity/1")) return Response.json(feeds++ === 0 ? [older] : [...posts].reverse().concat(older))
    if (path.endsWith("/office/threads/7")) return Response.json({ messages: posts.map((p, i) => ({ id: i + 1, author: "uqbar", body: p.text, at: p.at, kind: "chat" })), peek: null, window: null })
    if (path.endsWith("/office")) return Response.json({
      roster: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [],
      threads: [{ id: 7, title: "the plane thread", stage: null, awaiting: null, workspace_id: 1, lead: null }],
    })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-dogear-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-dogear-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
  server.stop(true)
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const deadline = Date.now() + 45_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)
const office = join(import.meta.dir, "..")
const start = async () => {
  tmux("new-session", "-d", "-x", "200", "-y", "60",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks OFFICE_WIDE=1 XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the workspace in the header", () => screen().includes("Toy"))
}
const read7 = async () => {
  keys("/")
  await until("FIND", () => screen().includes("FIND"))
  keys("-l", "plane thread")
  await until("the thread in the finder", () => screen().includes("#7 the plane thread"))
  keys("Enter")
  await until("the reader", () => screen().includes("post 4"))
}

test("a dog-ear survives a restart", async () => {
  await start()
  await until("the next refresh flies the posts", () => feeds >= 2)
  await Bun.sleep(300)
  await read7()
  await until("the caught post's paw", () => screen().includes("🐾"))
  tmux("kill-server")
  await start()
  await read7()
  await Bun.sleep(500)
  expect(screen()).toContain("🐾")
}, 60_000)
