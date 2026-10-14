import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

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
const deadline = Date.now() + 25_000
const until = async (what: string, ok: () => boolean) => {
  while (!ok() && Date.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what}; pane:\n${screen()}`)
}
const keys = (...k: string[]) => tmux("send-keys", "-t", "0", ...k)
const askLightsOut = async () => {
  keys("/")
  await until("FIND", () => screen().includes("FIND"))
  tmux("send-keys", "-t", "0", "-l", "lights out: stop")
  await until("the pick", () => screen().includes("lights out: stop everyone now"))
  keys("Enter")
  await until("the confirm", () => screen().includes("interrupt every pane ("))
}

test("a confirm: another key cancels and says so; enter is yes", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && OFFICE_SANDBOX=1 TMPDIR='${dir}' OFFICE_GRAPHICS=blocks XDG_STATE_HOME='${dir}' '${process.execPath}' tui/main.ts`)
  await until("the toy's workspace", () => screen().includes("Toy"))
  await askLightsOut()
  keys("x")
  await until("cancelled", () => screen().includes("cancelled") && !screen().includes("interrupt every pane ("))
  await askLightsOut()
  keys("Enter")
  await until("the write ran", () => screen().includes("it's a toy"))
  expect(screen()).not.toContain("interrupt every pane (")
}, 30_000)
