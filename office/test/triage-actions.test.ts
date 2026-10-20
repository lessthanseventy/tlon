import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// The triage card's lit row and the issue card: each item's own keys, through the real TUI against a stub server.
const blocker = { thread_id: 144, title: "the sheriff's beat", text: "the build is red", issue_id: 7, found_by: "scharlach", created_at: new Date(Date.now() - 3 * 3600_000).toISOString(), summary: "the build is red on main", evidence: "mix test: three failures in the room test, first red at four oh four" }
const check = { thread_id: 21, title: "a ticket at verify", text: "mix test", check_id: 9, slug: "workline:t:verify", stage: "verify" }
const unled = { thread_id: 22, title: "an orphan", text: "nobody leads it" }
const owned = { ...blocker, issue_id: 8, ticket_id: 452, ticket_status: "todo", summary: "a flake a ticket already took" }
let fixed = false, ownedOnly = false
const posts: { path: string; body: any }[] = []
const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const path = new URL(req.url).pathname
    if (req.method === "POST") { posts.push({ path, body: await req.json().catch(() => null) }); if (path.endsWith("/fix")) fixed = true; return Response.json({ ok: true, ticket_id: 3, owner: "routed to x" }, { status: 201 }) }
    if (path.endsWith("/office/triage/1")) return Response.json({ blockers: { shown: ownedOnly ? [owned] : fixed ? [] : [blocker], more: 0 }, failed_checks: { shown: [check], more: 0 }, unled: { shown: [unled], more: 0 }, count: 3 })
    if (path.endsWith("/office/needs")) return Response.json([])
    if (path.endsWith("/office")) return Response.json({ roster: [], threads: [], workspaces: [{ id: 1, name: "Toy" }], bench: [], tickets: [], triage: { "1": 3 } })
    return new Response("no", { status: 404 })
  },
})
const socket = `tlon-office-triage-${process.pid}`
const state = mkdtempSync(join(tmpdir(), "office-triage-"))
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
  const deadline = Date.now() + 20_000
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)

test("triage rows name the issue and carry the actions of the lit row; the issue card reads whole and acts", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  await until("the room", () => screen().includes("Toy"))
  keys("!")
  await until("the triage rows", () => screen().includes("#7") && screen().includes("scharlach"))
  expect(screen()).toMatch(/\$ +get it fixed/)
  expect(screen()).toMatch(/x +resolve/)
  expect(screen()).toMatch(/v +read the thread/)

  keys("Down", "Down") // the section headers are rows the cursor steps over
  await until("a failed check's action", () => /y +run verify again/.test(screen()))
  expect(screen()).not.toMatch(/get it fixed/)
  keys("Down", "Down", "Down")
  await until("an unled thread's action", () => /@ +hand it to/.test(screen()))

  keys("Up", "Up", "Up", "Up", "Up")
  keys("Enter")
  await until("the issue card", () => screen().includes("ISSUE #7"))
  expect(screen()).toContain("first red at four oh four")
  expect(screen()).toMatch(/scharlach/)

  keys("x")
  await until("the why prompt", () => /resolve — why/.test(screen()))
  keys("Escape")
  keys("$")
  await until("the fix posted", () => posts.some((p) => p.path.endsWith("/issues/7/fix")))
  await until("the card gone back to triage, the blocker gone", () => screen().includes("TRIAGE") && !screen().includes("#7"))
}, 60_000)

test("an issue a ticket took names it, and its key opens the ticket rather than filing another", async () => {
  ownedOnly = true
  // the first test's TUI, reused: a second boot is what a loaded gate can't fit in the budget
  if (!screen().includes("Toy") && !screen().includes("TRIAGE")) {
    const office = join(import.meta.dir, "..")
    tmux("new-session", "-d", "-x", "150", "-y", "50",
      `cd '${office}' && TLON_URL='http://127.0.0.1:${server.port}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts`)
  }
  keys("Escape")
  await until("the room", () => screen().includes("Toy") && !screen().includes("TRIAGE"))
  keys("!")
  await until("the owned issue's row", () => screen().includes("#8") && screen().includes("→ ticket #452 todo"))
  expect(screen()).toMatch(/\$ +open ticket #452/)
  expect(screen()).not.toMatch(/get it fixed/)
}, 40_000)
