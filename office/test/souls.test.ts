import { afterEach, describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { seatLine, SEAT_VOICE } from "../kit/seat-voices"
import { SOUL_SECTIONS, corkLabel, diaryEntries, parseSoul, soulLines, spoken, soulFor, soulNote, soulsGen, useSouls } from "../kit/souls"
import { loadSouls, soulsSignature } from "../tui/souls"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { office } from "./golden"

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
  test("a heading named like an Object member is just a heading", () => {
    const s = parseSoul("## constructor\nx\n## __proto__\ny\n## toString\nz\n")
    expect(s.sections["constructor"]).toBe("x")
    expect(s.sections["__proto__"]).toBe("y")
    expect(s.sections["toString"]).toBe("z")
  })
  test("a CRLF file leaves no carriage returns in headings or sections", () => {
    const s = parseSoul("## Wants\r\nsleep\r\nmore sleep\r\n")
    expect(s.sections["Wants"]).toBe("sleep\nmore sleep")
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

describe("soulLines", () => {
  test("the card lists each filled section as a heading and its text, Diary last", () => {
    expect(soulLines(parseSoul("## Diary\nd\n\n## Wants\nw\n## Fears\n"))).toEqual([
      { head: "Wants", text: "w" }, { head: "Diary", text: "d" },
    ])
  })
  test("a file with no headings shows raw", () => {
    expect(soulLines(parseSoul("just words\n"))).toEqual([{ head: "", text: "just words" }])
  })
  test("an empty file shows nothing", () => {
    expect(soulLines(parseSoul(""))).toEqual([])
  })
})

describe("soulNote", () => {
  test("People says it is read by verb; no other section has a note", () => {
    expect(soulNote("People")).toMatch(/read by verb.*admires.*needles.*would cover for/)
    for (const h of SOUL_SECTIONS.filter(h => h !== "People")) expect(soulNote(h)).toBeUndefined()
  })
})

describe("the diary speaks", () => {
  afterEach(() => useSouls({}))
  const soul = parseSoul("## Diary\n- Oct 2: wrote a stanza on Uruguay.\n- Oct 9: fixed the foosball table.\n")
  test("entries are bare bullets, said without the date", () => {
    expect(diaryEntries(soul)).toEqual(["Oct 2: wrote a stanza on Uruguay.", "Oct 9: fixed the foosball table."])
    expect(diaryEntries(parseSoul(""))).toEqual([])
    expect(spoken("Oct 2: wrote a stanza on Uruguay.")).toBe("Wrote a stanza on Uruguay.")
  })
  test("a seat with a diary quotes it now and then, the rest of the time its own banter", () => {
    useSouls({ hronir: soul })
    const said = Array.from({ length: 600 }, () => seatLine("hronir", []))
    const quotes = said.filter((l) => ["Wrote a stanza on Uruguay.", "Fixed the foosball table."].includes(l))
    expect(quotes.length).toBeGreaterThan(20)
    expect(quotes.length).toBeLessThan(120)
    expect(said.filter((l) => !quotes.includes(l)).every((l) => SEAT_VOICE.hronir!.banter.includes(l))).toBe(true)
  })
  test("a seat without a diary never quotes", () => {
    useSouls({ hronir: parseSoul("## Wants\nw") })
    expect(Array.from({ length: 200 }, () => seatLine("hronir", [])).every((l) => SEAT_VOICE.hronir!.banter.includes(l))).toBe(true)
  })
})

describe("side projects on the corkboard", () => {
  const note = (id: number, author: string, kind: string) => ({ id, author, kind, body: `n${id}`, re: null, at: id })
  const board = [note(9, "daneri", "side project"), note(7, "ashe", "side project"), note(5, "daneri", "joke"), note(3, "daneri", "side project")]
  test("each side-project note says which step of its author's project it is, over the notes on the board", () => {
    expect(corkLabel(board, board[3]!)).toBe("side project 1")
    expect(corkLabel(board, board[0]!)).toBe("side project 2")
    expect(corkLabel(board, board[1]!)).toBe("side project 1")
  })
  test("any other note is just its kind", () => expect(corkLabel(board, board[2]!)).toBe("joke"))
  test("after two days the board's tips for Daneri's poem name stanzas 1 and 2", () => {
    const r = new WideRoom(696)
    r.pinboard(board.map((n) => ({ ...n, kind: n.kind as never })))
    const fr = r.render(viewOf(office(2), 1), { picked: null, person: null }, (s) => s.length * 2, new Date(2026, 9, 5, 15, 0))
    const tips = fr.hits.map((h) => h.tip ?? "")
    expect(tips.some((t) => t.startsWith("daneri (side project 2): n9"))).toBe(true)
    expect(tips.some((t) => t.startsWith("daneri (side project 1): n3"))).toBe(true)
  })
})
