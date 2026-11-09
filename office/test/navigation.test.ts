import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { killServer } from "./kill-server"
import { started, TUI_TEST } from "./started"
import { waitFor } from "./wait-for"

// Drives the real TUI on the toy world: esc is one step back (to the card you came from), a status
// line does not outlive the card it was said on, and words that did not send come back.
const state = mkdtempSync(join(tmpdir(), "office-nav-"))
let socket = ""
let starts = 0
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)
const text = (s: string) => tmux("send-keys", "-t", "0", "-l", s)
afterAll(() => {
  killServer(socket)
  rmSync(state, { recursive: true, force: true })
})

async function start() {
  // a socket killed a moment ago may still be dying: each start gets its own
  socket = `tlon-office-nav-${process.pid}-${++starts}`
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && TMPDIR='${state}' OFFICE_GRAPHICS=blocks OFFICE_NO_ANIMATE=1 XDG_STATE_HOME='${state}' '${process.execPath}' tui/main.ts --sandbox`)
  await started(tmux, "the toy", () => screen().includes("Toy"))
}

test("esc steps back through the cards you came by, and the status line stays on its card", async () => {
  await start()
  keys("E", "5")
  await waitFor(screen, "treat! they come running", "the treat said")
  keys("c")
  await waitFor(screen, "CREW · ", "the crew card")
  expect(screen()).not.toContain("treat! they come running")
  keys("Enter")
  await waitFor(screen, () => !screen().includes("CREW · ") && screen().includes("ACTIONS"), "a person card")
  const person = screen()
  keys("Escape")
  await waitFor(screen, "CREW · ", "back on the crew")
  keys("Enter"); await waitFor(screen, () => screen() === person || !screen().includes("CREW · "), "the person again")
  text("\\")
  await waitFor(screen, "hair", "the look card")
  keys("Escape")
  await waitFor(screen, () => !screen().includes("hair") && !screen().includes("CREW · "), "back on the person")
  keys("Escape")
  await waitFor(screen, "CREW · ", "back on the crew")
}, TUI_TEST)

test("words that did not send come back when the box is opened again", async () => {
  keys("Escape")
  await Bun.sleep(300) // esc has no visible effect to wait on: let it be handled before the next
  keys("Escape")
  text("'")
  await waitFor(screen, "say to the office", "the office input")
  text("hello team")
  keys("Enter")
  await waitFor(screen, "it's a toy", "the failure said")
  text("'")
  await waitFor(screen, "hello team", "the draft back")
}, 40_000)

test("the finder has a verb for the tickets board and does not list unrelated rows for a name", async () => {
  keys("Escape")
  await Bun.sleep(300) // esc has no visible effect to wait on: let it be handled before the next
  keys("Escape")
  text("/")
  text("nina")
  // the query echoes key by key, and a partial "ni" rightly matches more: assert once all of it is in
  await waitFor(screen, () => /FIND\b.*: nina\b/.test(screen()) && screen().includes("Nina, the cat"), "nina in the finder")
  expect(screen()).not.toContain("settings: the running")
  keys("Escape")
  text("/")
  text("tickets")
  keys("Enter")
  await waitFor(screen, "TICKETS · ", "the tickets column")
}, 40_000)

// esc has no visible effect to wait on: let each be handled before the next
const home = async () => { keys("Escape"); await Bun.sleep(250); keys("Escape"); await Bun.sleep(250) }

test("cards say what they hold: the inherited model, the current workspace, an empty list, the pet's species", async () => {
  await home()
  text("o")
  await waitFor(screen, "nothing here yet — n pin a note", "the empty notes card")
  await home()
  text("O")
  await waitFor(screen, "WORKSPACES", "the workspaces card")
  expect(screen()).toContain("◆ Toy")
  expect(screen()).not.toContain("▸ ▸")
  await home()
  keys("Tab")
  await waitFor(screen, "(archetype's)", "a person card")
  expect(screen()).toMatch(/anthropic\/claude-\w+ \(archetype's\)/)
  expect(screen()).not.toContain("·  (archetype's)")
  await home()
  text("/"); text("nina, the cat"); keys("Enter")
  await waitFor(screen, "your cat, and a princess", "Nina's card")
  const row = screen().split("\n").findIndex((l) => l.includes("species")) + 1
  text(`\x1b[<0;8;${row}M\x1b[<0;8;${row}m`)
  await waitFor(screen, "your rabbit", "the species cycled")
  expect(screen()).not.toContain("princess")
}, 60_000)

test("a toy fired from the play card lands back on the card you opened it from", async () => {
  killServer(socket)
  await start()
  keys("c")
  await waitFor(screen, "CREW · ", "the crew card")
  keys("Enter")
  await waitFor(screen, () => !screen().includes("CREW · ") && screen().includes("ACTIONS"), "a person card")
  keys("E", "8")
  await waitFor(screen, "pat pat", "the pat")
  expect(screen()).toContain("SCHARLACH  ─")
  expect(screen()).not.toContain("HOME  ─")
}, TUI_TEST)
