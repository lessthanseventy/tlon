import { describe, expect, test } from "bun:test"
import { ENTER, LEAVE, tokenize } from "../tui/term"

describe("shift+arrow keys", () => {
  test("xterm SGR shift-modified arrows tokenize to shift-up/down/left/right", () => {
    expect(tokenize("\x1b[1;2A").inputs).toEqual([{ t: "key", key: "shift-up" }])
    expect(tokenize("\x1b[1;2B").inputs).toEqual([{ t: "key", key: "shift-down" }])
    expect(tokenize("\x1b[1;2C").inputs).toEqual([{ t: "key", key: "shift-right" }])
    expect(tokenize("\x1b[1;2D").inputs).toEqual([{ t: "key", key: "shift-left" }])
  })
})

describe("focus reports", () => {
  test("focus reports are their own input, not keys", () => {
    expect(tokenize("\x1b[I").inputs).toEqual([{ t: "focus", on: true }])
    expect(tokenize("\x1b[O").inputs).toEqual([{ t: "focus", on: false }])
    expect(tokenize("a\x1b[Ib").inputs.map((i) => i.t)).toEqual(["key", "focus", "key"])
  })
  test("entering turns focus reporting on and leaving turns it off", () => {
    expect(ENTER).toContain("\x1b[?1004h")
    expect(LEAVE).toContain("\x1b[?1004l")
  })
})
