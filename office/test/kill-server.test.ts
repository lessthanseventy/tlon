import { expect, test } from "bun:test"
import { existsSync } from "node:fs"
import { killServer } from "./kill-server"

const dec = new TextDecoder()

test("killServer takes the server down and removes its socket file, wherever TMUX_TMPDIR points", () => {
  const sock = `tlon-office-kill-server-${process.pid}`
  Bun.spawnSync(["tmux", "-L", sock, "new-session", "-d", "cat"])
  const path = dec.decode(Bun.spawnSync(["tmux", "-L", sock, "display", "-p", "#{socket_path}"]).stdout).trim()
  expect(existsSync(path)).toBe(true)
  // a poisoned process.env must not aim the removal elsewhere
  const was = process.env.TMUX_TMPDIR
  process.env.TMUX_TMPDIR = "/nonexistent"
  try { killServer(sock) } finally { if (was === undefined) delete process.env.TMUX_TMPDIR; else process.env.TMUX_TMPDIR = was }
  expect(existsSync(path)).toBe(false)
  expect(Bun.spawnSync(["tmux", "-L", sock, "ls"]).exitCode).not.toBe(0)
})

test("killServer on a name with no server is a no-op", () => {
  expect(() => killServer(`tlon-office-kill-server-none-${process.pid}`)).not.toThrow()
})
