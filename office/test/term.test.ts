import { describe, expect, test } from "bun:test"
import { enter, leave, tokenize } from "../tui/term"

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
  test("enter turns focus reporting on and leave turns it off", () => {
    const writes: string[] = []
    const real = process.stdout.write.bind(process.stdout)
    const stdin = process.stdin as unknown as { setRawMode: unknown; resume: unknown }
    const saved = { raw: stdin.setRawMode, resume: stdin.resume }
    stdin.setRawMode = () => {}
    stdin.resume = () => {}
    process.stdout.write = ((s: string) => (writes.push(s), true)) as typeof process.stdout.write
    try {
      enter()
      leave()
    } finally {
      process.stdout.write = real
      stdin.setRawMode = saved.raw
      stdin.resume = saved.resume
    }
    expect(writes[0]).toContain("\x1b[?1004h")
    expect(writes[1]).toContain("\x1b[?1004l")
  })
})
