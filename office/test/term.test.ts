import { describe, expect, test } from "bun:test"
import { tokenize } from "../tui/term"

describe("shift+arrow keys", () => {
  test("xterm SGR shift-modified arrows tokenize to shift-up/down/left/right", () => {
    expect(tokenize("\x1b[1;2A").inputs).toEqual([{ t: "key", key: "shift-up" }])
    expect(tokenize("\x1b[1;2B").inputs).toEqual([{ t: "key", key: "shift-down" }])
    expect(tokenize("\x1b[1;2C").inputs).toEqual([{ t: "key", key: "shift-right" }])
    expect(tokenize("\x1b[1;2D").inputs).toEqual([{ t: "key", key: "shift-left" }])
  })
})
