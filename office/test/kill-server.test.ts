import { expect, test } from "bun:test"
import { existsSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
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

test("killServer removes the socket of a server whose only pane already exited", () => {
  // a private TMUX_TMPDIR, so the sweep of the real /tmp/tmux-<uid> is never touched by this test
  // Bun.spawnSync reads the environment it started with, so the tmux calls here carry the private dir
  // explicitly, and killServer's fallback reads process.env, which is set to the same dir
  const dir = mkdtempSync(join(tmpdir(), "kill-server-"))
  const was = process.env.TMUX_TMPDIR
  process.env.TMUX_TMPDIR = dir
  const env = { ...process.env, TMUX_TMPDIR: dir }
  const sock = `tlon-office-kill-server-gone-${process.pid}`
  const path = join(dir, `tmux-${process.getuid!()}`, sock)
  const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", sock, ...a], { env })
  try {
    tmux("new-session", "-d", "true")
    // the pane is `true`: the server exits on its own, and tmux answers nothing for it afterwards
    for (let i = 0; i < 50 && tmux("ls").exitCode === 0; i++) Bun.sleepSync(20)
    expect(tmux("ls").exitCode).not.toBe(0)
    expect(existsSync(path)).toBe(true)
    killServer(sock)
    expect(existsSync(path)).toBe(false)
  } finally {
    if (was === undefined) delete process.env.TMUX_TMPDIR; else process.env.TMUX_TMPDIR = was
    rmSync(dir, { recursive: true, force: true })
  }
})

test("killServer on a name with no server is a no-op", () => {
  expect(() => killServer(`tlon-office-kill-server-none-${process.pid}`)).not.toThrow()
})
