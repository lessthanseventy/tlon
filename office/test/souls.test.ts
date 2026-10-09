import { afterEach, describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { loadSouls, parseSoul, soulFor, soulsGen, soulsSignature, useSouls } from "../kit/souls"

const FIXTURE = await Bun.file(join(import.meta.dir, "fixtures/daneri.md")).text()

describe("parseSoul", () => {
  test("the design's headings become sections, Diary included", () => {
    const s = parseSoul(FIXTURE)
    expect(s.sections["Where they're from"]).toBe("Buenos Aires, the house on Calle Garay.")
    expect(s.sections["Wants"]).toBe("To finish The Earth.")
    expect(s.sections["The side project"]).toBe("The Earth, a poem.")
    expect(s.sections["Diary"]).toBe("- Oct 2: wrote a stanza on Uruguay.")
    expect(s.raw).toBe(FIXTURE)
  })
  test("missing sections are empty", () => {
    const s = parseSoul("## Wants\nsleep\n")
    expect(s.sections["Fears"]).toBe("")
    expect(s.sections["Wants"]).toBe("sleep")
  })
  test("unknown headings are kept", () => {
    expect(parseSoul("## Hobbies\nchess\n").sections["Hobbies"]).toBe("chess")
  })
  test("garbage with no headings never throws and keeps the raw text", () => {
    const s = parseSoul("just some words\n\0\u{1F4A9}")
    expect(s.raw).toBe("just some words\n\0\u{1F4A9}")
    expect(s.sections["Wants"]).toBe("")
  })
})

describe("souls table", () => {
  test("useSouls replaces the table and bumps the gen", () => {
    const g = soulsGen()
    useSouls({ daneri: parseSoul(FIXTURE) })
    expect(soulsGen()).toBe(g + 1)
    expect(soulFor("daneri")?.sections["Fears"]).toBe("Being brief.")
    expect(soulFor("ashe")).toBeUndefined()
    useSouls({})
  })
})

describe("polling a souls dir", () => {
  let dir = ""
  afterEach(() => { if (dir) rmSync(dir, { recursive: true, force: true }); dir = "" })
  test("a missing dir is no souls and no error", () => {
    expect(loadSouls("/nonexistent/souls")).toEqual({})
    expect(soulsSignature("/nonexistent/souls")).toBe("")
  })
  test("a file written then edited shows up, and the signature moves", () => {
    dir = mkdtempSync(join(tmpdir(), "souls-"))
    const f = join(dir, "daneri.md")
    writeFileSync(f, FIXTURE)
    writeFileSync(join(dir, "notes.txt"), "not a soul")
    const sig = soulsSignature(dir)
    expect(Object.keys(loadSouls(dir))).toEqual(["daneri"])
    useSouls(loadSouls(dir))
    expect(soulFor("daneri")?.sections["Fears"]).toBe("Being brief.")
    writeFileSync(f, FIXTURE.replace("Being brief.", "Silence."))
    utimesSync(f, new Date(), new Date(Date.now() + 5000))
    expect(soulsSignature(dir)).not.toBe(sig)
    useSouls(loadSouls(dir))
    expect(soulFor("daneri")?.sections["Fears"]).toBe("Silence.")
    useSouls({})
  })
})
