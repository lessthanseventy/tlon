import { afterAll, expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

// R reloads the TUI by exec, never by a child: a waiting parent stays alive, one per reload
const fixture = join(import.meta.dir, "fixtures/exec-self.ts")
const dir = mkdtempSync(join(tmpdir(), "office-exec-"))
afterAll(() => rmSync(dir, { recursive: true, force: true }))

const execsOnce = (cmd: string[]) => {
  // a lost argument re-execs forever: the timeout ends it
  const r = Bun.spawnSync(cmd, { timeout: 10_000 })
  const [before, after] = r.stdout.toString().trim().split("\n")
  expect(after).toBe(`after ${before!.split(" ")[1]} carried`)
  expect(r.exitCode).toBe(7)
}

test("execSelf replaces the process: same pid, its env, its exit code", () => execsOnce([process.execPath, fixture]))

test("so does a compiled binary's, its arguments intact", () => {
  const out = join(dir, "exec-self")
  expect(Bun.spawnSync([process.execPath, "build", "--compile", fixture, "--outfile", out]).exitCode).toBe(0)
  execsOnce([out])
}, 60_000)
