import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { started, TUI_TEST } from "./started"
import { waitFor } from "./wait-for"

// A confirm takes y or enter as yes; any other key cancels, and says so. Driven in the sandbox,
// where the confirmed write is the toy's refusal, so nothing real is paused.
const dec = new TextDecoder()
const socket = `tlon-office-confirm-${process.pid}`
const dir = mkdtempSync(join(tmpdir(), "office-confirm-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(dir, { recursive: true, force: true })
})
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)
const askLightsOut = async () => {
  keys("/")
  await waitFor(screen, "FIND", "FIND")
  tmux("send-keys", "-t", "0", "-l", "lights out: stop")
  await waitFor(screen, "lights out: stop everyone now", "the pick")
  keys("Enter")
  await waitFor(screen, "interrupt every pane (", "the confirm")
}

test("a confirm: another key cancels and says so; enter is yes", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && OFFICE_SANDBOX=1 TMPDIR='${dir}' OFFICE_GRAPHICS=blocks OFFICE_NO_ANIMATE=1 XDG_STATE_HOME='${dir}' '${process.execPath}' tui/main.ts`)
  await started(tmux, "the toy's workspace", () => screen().includes("Toy"))
  await askLightsOut()
  keys("x")
  await waitFor(screen, () => screen().includes("cancelled") && !screen().includes("interrupt every pane ("), "cancelled")
  await askLightsOut()
  keys("Enter")
  await waitFor(screen, "it's a toy", "the write ran")
  expect(screen()).not.toContain("interrupt every pane (")
}, TUI_TEST)
