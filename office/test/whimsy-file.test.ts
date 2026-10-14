import { expect, test } from "bun:test"
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { load, save } from "../kit/whimsy-file"
import { DEFAULT, setDial, setPreset } from "../kit/whimsy"

const dir = () => mkdtempSync(join(tmpdir(), "whimsy-"))

test("a missing file is the defaults", () => {
  expect(load(join(dir(), "office.json"))).toEqual(DEFAULT)
})
test("save then load round-trips, creating the directory", () => {
  const p = join(dir(), "nested", "office.json")
  const s = setDial(setPreset(DEFAULT, "rimworld"), "banter", false)
  save(p, s)
  expect(load(p)).toEqual(s)
})
test("garbage is the defaults", () => {
  const p = join(dir(), "office.json")
  writeFileSync(p, "{{{")
  expect(load(p)).toEqual(DEFAULT)
})
test("an unwritable path does not throw", () => {
  expect(() => save("/proc/nope/office.json", DEFAULT)).not.toThrow()
})
