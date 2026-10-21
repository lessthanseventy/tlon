import { afterEach, expect, test } from "bun:test"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { castSignature, loadCast, saveCast, setTrait } from "../kit/cast"

const made: string[] = []
const dir = () => {
  const d = mkdtempSync(join(tmpdir(), "cast-file-"))
  made.push(d)
  return d
}
afterEach(() => {
  for (const d of made.splice(0)) rmSync(d, { recursive: true, force: true })
})

test("a missing file is an empty cast", () => expect(loadCast(join(dir(), "cast.json"))).toEqual({}))
test("a garbled file is an empty cast", () => {
  const p = join(dir(), "cast.json"); writeFileSync(p, "{not json")
  expect(loadCast(p)).toEqual({})
})
test("round trip keeps grade and specialty by seat name", () => {
  const p = join(dir(), "sub", "cast.json")
  saveCast(p, setTrait(setTrait({}, "ada", "grade", "senior"), "ada", "specialty", "office"))
  expect(loadCast(p)).toEqual({ ada: { grade: "senior", specialty: "office" } })
})
test("a key that is not a legal seat name, and a non-string value, are dropped on load", () => {
  const p = join(dir(), "cast.json")
  writeFileSync(p, JSON.stringify({ "Bad Name": { grade: "x" }, ok: { grade: 3, specialty: "server" } }))
  expect(loadCast(p)).toEqual({ ok: { specialty: "server" } })
})
test("setTrait does not mutate", () => {
  const a = {}; setTrait(a, "ada", "grade", "junior"); expect(a).toEqual({})
})
test("signature changes when the file does, and is empty when absent", () => {
  const p = join(dir(), "cast.json")
  expect(castSignature(p)).toBe("")
  saveCast(p, { ada: { grade: "junior" } })
  expect(castSignature(p)).not.toBe("")
})
