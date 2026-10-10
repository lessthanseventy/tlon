import { afterAll, expect, test } from "bun:test"
import { rmSync } from "node:fs"
import { rows, TerminalView, unescape } from "../tui/terminal"

const enc = new TextEncoder(), dec = new TextDecoder()

test("control mode's octal escapes come back as the bytes they stand for", () => {
  expect(dec.decode(unescape(enc.encode("a\\033[1mb\\134c\\015\\012")))).toBe("a\x1b[1mb\\c\r\n")
  expect(dec.decode(unescape(enc.encode("héllo \\12 tail\\")))).toBe("héllo \\12 tail\\")
})

// a private tmux server, so nothing live is touched
const socket = `tlon-office-test-${process.pid}`
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
// tmux leaves its socket file behind when its server dies
const killServer = (sock: string) => {
  Bun.spawnSync(["tmux", "-L", sock, "kill-server"])
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${sock}`, { force: true })
}
afterAll(() => killServer(socket))

test("a window's screen arrives, keys typed into it come back", async () => {
  tmux("new-session", "-d", "-s", "w9", "-n", "lead", "-x", "60", "-y", "10", "sh -c 'printf \"hello from the pane\\n\"; exec cat'")
  // conditions waited on, never fixed sleeps: under load (a gate beside coworkers' suites) the fixed
  // waits outran bun's 5 s budget
  const until = async (ok: () => boolean) => { for (let i = 0; i < 300 && !ok(); i++) await Bun.sleep(50) }
  const sessions = () => dec.decode(tmux("ls", "-F", "#{session_name}").stdout).trim()
  await until(() => sessions() === "w9")
  let changes = 0
  const view = new TerminalView({ socket, session: "w9", window: "lead" }, 40, 8, () => changes++, () => {})
  const text = () => rows(view.vt).map((r) => r.replace(/\x1b\[[0-9;]*m/g, "")).join("\n")
  await until(() => text().includes("hello from the pane"))
  expect(text()).toContain("hello from the pane")
  view.send(enc.encode("typed back\r"))
  await until(() => (text().match(/typed back/g) ?? []).length >= 2)
  expect((text().match(/typed back/g) ?? []).length).toBe(2) // the tty's echo and cat's copy
  expect(changes).toBeGreaterThan(0)
  expect(rows(view.vt).every((r) => r.replace(/\x1b\[[0-9;]*m/g, "").length === 40)).toBe(true)
  // only our throwaway session went away; the coworker's stays
  view.close()
  await until(() => sessions() === "w9")
  expect(sessions()).toBe("w9")
}, 30_000)

test("the placeholder window's own output never reaches the view — only the coworker's pane does", async () => {
  const sock = `tlon-office-test-ph-${process.pid}`
  const t = (...a: string[]) => Bun.spawnSync(["tmux", "-L", sock, ...a])
  try {
    t("new-session", "-d", "-s", "w8", "-n", "lead", "-x", "60", "-y", "10", "sh -c 'printf \"the coworker\\n\"; exec cat'")
    // the shell a control-mode client's placeholder window runs: a login shell's banner (a fortune) in life
    t("set-option", "-g", "default-command", "printf 'from the placeholder\\n'; exec cat")
    const until = async (ok: () => boolean) => { for (let i = 0; i < 300 && !ok(); i++) await Bun.sleep(50) }
    const view = new TerminalView({ socket: sock, session: "w8", window: "lead" }, 40, 8, () => {}, () => {})
    const text = () => rows(view.vt).map((r) => r.replace(/\x1b\[[0-9;]*m/g, "")).join("\n")
    await until(() => text().includes("the coworker"))
    await Bun.sleep(200)
    expect(text()).toContain("the coworker")
    expect(text()).not.toContain("from the placeholder")
    view.close()
  } finally {
    killServer(sock)
  }
}, 30_000)
