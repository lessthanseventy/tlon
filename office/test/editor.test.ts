import { describe, expect, test } from "bun:test"
import { Editor, wrap } from "../tui/editor"
import { rank, score } from "../tui/fuzzy"
import { tokenize } from "../tui/term"
import { parseWhen, showWhen } from "../tui/when"

describe("wrap", () => {
  test("breaks at words, keeps explicit newlines, splits a word too long for a row", () => {
    expect(wrap("the quick brown fox", 10)).toEqual(["the quick", "brown fox"])
    expect(wrap("a\n\nb", 10)).toEqual(["a", "", "b"])
    expect(wrap("abcdefghij", 4)).toEqual(["abcd", "efgh", "ij"])
  })
})

describe("Editor", () => {
  const typed = (keys: string[], ed = new Editor()) => { keys.forEach((k) => ed.key(k)); return ed }
  test("types, breaks a line on alt-enter, joins it back on backspace", () => {
    const ed = typed(["h", "i", "alt-enter", "y", "o"])
    expect(ed.text).toBe("hi\nyo")
    typed(["home", "backspace"], ed)
    expect(ed.text).toBe("hiyo")
    expect(ed.key("enter")).toBe(false)
  })
  test("the readline kills: ^w a word, ^u to the start, ^k to the end", () => {
    expect(typed(["ctrl-w"], new Editor("ship the clock")).text).toBe("ship the ")
    const ed = new Editor("ship the clock"); ed.col = 4
    expect(typed(["ctrl-k"], ed).text).toBe("ship")
    expect(typed(["ctrl-u"], new Editor("ship")).text).toBe("")
  })
  test("a paste keeps its lines; a one-line editor flattens them", () => {
    const ed = new Editor(); ed.insert("a\r\nb")
    expect(ed.text).toBe("a\nb")
    const one = new Editor("", false); one.insert("a\nb")
    expect(one.text).toBe("a b")
    expect(one.key("alt-enter")).toBe(false)
  })
  test("view soft-wraps and keeps the cursor in sight", () => {
    const v = new Editor("abcdefgh\nxy").view(4, 2)
    expect(v.rows).toEqual(["efgh", "xy"])
    expect(v.cursor).toEqual({ r: 1, c: 2 })
  })
})

describe("fuzzy", () => {
  test("letters in order match; word starts beat scattered letters", () => {
    expect(score("xyz", "the clock")).toBeNull()
    expect(rank("cl", ["a cool lamp", "clock", "uncle"], (s) => s)[0]).toBe("clock")
  })
})

describe("tokenize: what the composer needs", () => {
  test("a bracketed paste is one input, newlines and all; ctrl keys and alt-enter have names", () => {
    const { inputs } = tokenize("\x1b[200~a\rb\x1b[201~\x17\x1b\r\x1b[13;2u\x1b[3~")
    expect(inputs).toEqual([
      { t: "paste", text: "a\rb" }, { t: "key", key: "ctrl-w" }, { t: "key", key: "alt-enter" },
      { t: "key", key: "shift-enter" }, { t: "key", key: "delete" },
    ])
  })
  test("a paste split across reads waits for its end", () => {
    const a = tokenize("\x1b[200~half")
    expect(a.inputs).toEqual([])
    expect(tokenize(a.rest + " more\x1b[201~").inputs).toEqual([{ t: "paste", text: "half more" }])
  })
})

describe("when", () => {
  const now = new Date(2026, 9, 5, 18, 0)
  test("a cron passes through; a time is a one-off in local time", () => {
    expect(parseWhen("0 9 * * 1-5", now)).toEqual({ cron: "0 9 * * 1-5", at: null })
    expect(parseWhen("@daily", now)).toEqual({ cron: "@daily", at: null })
    expect(parseWhen("in 2h", now)).toEqual({ cron: null, at: new Date(2026, 9, 5, 20, 0).toISOString() })
    expect(parseWhen("2026-10-06 14:30", now)).toEqual({ cron: null, at: new Date(2026, 9, 6, 14, 30).toISOString() })
    expect(parseWhen("", now)).toBeNull()
  })
  test("a bare time already past today is tomorrow's; a one-off shows back as typed", () => {
    expect(parseWhen("09:00", now)!.at).toBe(new Date(2026, 9, 6, 9, 0).toISOString())
    expect(showWhen(parseWhen("2026-10-06 14:30", now)!)).toBe("2026-10-06 14:30")
  })
})
