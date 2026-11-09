import { expect, test } from "bun:test"
import { mkdtempSync, renameSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { watchDirs } from "../tui/watch"

test("a change in a watched directory, a replaced file included, calls back once, debounced", async () => {
  const dir = mkdtempSync(join(tmpdir(), "watch-"))
  let n = 0
  let w!: ReturnType<typeof watchDirs>
  const seen = new Promise<void>((done) => { w = watchDirs([dir, dir], () => { n++; done() }, 20) })
  expect(w.ok).toBe(true)
  writeFileSync(join(dir, "a.json.tmp"), "{}")
  renameSync(join(dir, "a.json.tmp"), join(dir, "a.json"))
  await seen
  await Bun.sleep(100)
  w.close()
  expect(n).toBe(1)
})

test("a directory that is not there is reported, not thrown", () => {
  const w = watchDirs([join(tmpdir(), "no-such-watch-dir")], () => {})
  expect(w.ok).toBe(false)
  w.close()
})
