import { describe, expect, test } from "bun:test"
import { mute, out } from "../tui/term"

// A relaunched office hands the terminal to its child: the parent must not write another byte, or
// two rooms paint the same window on alternate frames (the strobe that sent Andrew a seizure warning).
describe("out after mute", () => {
  test("writes nothing once muted", () => {
    const writes: string[] = []
    const real = process.stdout.write.bind(process.stdout)
    process.stdout.write = ((s: string) => (writes.push(s), true)) as typeof process.stdout.write
    try {
      out("before")
      mute()
      out("after")
    } finally {
      process.stdout.write = real
    }
    expect(writes).toEqual(["before"])
  })
})
