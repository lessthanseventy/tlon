import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Drives the real TUI on the toy world: esc is one step back (to the card you came from), a status
// line does not outlive the card it was said on, and words that did not send come back.
const state = mkdtempSync(join(tmpdir(), "office-nav-"))
let socket = ""
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)
const text = (s: string) => tmux("send-keys", "-t", "0", "-l", s)
const until = async (what: string, ok: () => boolean) => {
  const deadline = performance.now() + 25_000
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
afterAll(() => {
  Bun.spawnSync(["tmux", "-L", socket, "kill-server"])
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(state, { recursive: true, force: true })
})

async function start() {
  socket = `tlon-office-nav-${process.pid}`
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TMPDIR='${state}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts --sandbox`)
  await until("the toy", () => screen().includes("Toy"))
}

test("esc steps back through the cards you came by, and the status line stays on its card", async () => {
  await start()
  keys("T")
  await until("the treat said", () => screen().includes("treat! they come running"))
  keys("c")
  await until("the crew card", () => screen().includes("CREW · "))
  expect(screen()).not.toContain("treat! they come running")
  keys("Enter")
  await until("a person card", () => !screen().includes("CREW · ") && screen().includes("ACTIONS"))
  const person = screen()
  keys("Escape")
  await until("back on the crew", () => screen().includes("CREW · "))
  keys("Enter"); await until("the person again", () => screen() === person || !screen().includes("CREW · "))
  text("\\")
  await until("the look card", () => screen().includes("hair"))
  keys("Escape")
  await until("back on the person", () => !screen().includes("hair") && !screen().includes("CREW · "))
  keys("Escape")
  await until("back on the crew", () => screen().includes("CREW · "))
}, 60_000)

test("words that did not send come back when the box is opened again", async () => {
  keys("Escape")
  await Bun.sleep(300)
  keys("Escape")
  text("'")
  await until("the office input", () => screen().includes("say to the office"))
  text("hello team")
  keys("Enter")
  await until("the failure said", () => screen().includes("it's a toy"))
  text("'")
  await until("the draft back", () => screen().includes("hello team"))
}, 40_000)

test("the finder has a verb for the tickets board and does not list unrelated rows for a name", async () => {
  keys("Escape")
  await Bun.sleep(300)
  keys("Escape")
  text("/")
  text("nina")
  await until("nina in the finder", () => screen().includes("Nina, the cat"))
  expect(screen()).not.toContain("settings: the running")
  keys("Escape")
  text("/")
  text("tickets")
  keys("Enter")
  await until("the tickets column", () => screen().includes("TICKETS · "))
}, 40_000)
