import { describe, expect, test } from "bun:test"
import { Scene } from "../kit/draw"
import { drawMailbox, mailbox, MAX_LETTERS } from "../kit/mailbox"

const need = (level: "blocking" | "decide") => ({ level })

describe("mailbox", () => {
  test("empty needs: no letters, flag down", () => {
    expect(mailbox([])).toEqual({ letters: 0, blocking: 0, flagUp: false, total: 0 })
  })
  test("each need is a letter; blocking ones raise the flag", () => {
    expect(mailbox([need("decide"), need("decide")])).toEqual({ letters: 2, blocking: 0, flagUp: false, total: 2 })
    expect(mailbox([need("decide"), need("blocking")])).toEqual({ letters: 2, blocking: 1, flagUp: true, total: 2 })
  })
  test("a full box stops drawing letters at the cap but still counts them", () => {
    const m = mailbox(Array.from({ length: MAX_LETTERS + 4 }, () => need("decide")))
    expect(m.letters).toBe(MAX_LETTERS)
    expect(m.total).toBe(MAX_LETTERS + 4)
  })
})

describe("drawMailbox", () => {
  const paint = (mb: ReturnType<typeof mailbox>) => {
    const sc = new Scene(40, 40, 0)
    drawMailbox(sc, 10, 30, mb)
    sc.finish()
    return Buffer.from(sc.cv.rgba)
  }
  test("a mailbox with mail looks different from an empty one", () => {
    expect(paint(mailbox([need("decide")])).equals(paint(mailbox([])))).toBe(false)
  })
  test("the raised flag shows", () => {
    expect(paint(mailbox([need("blocking")])).equals(paint(mailbox([need("decide")])))).toBe(false)
  })
  test("the empty mailbox still draws (it is furniture)", () => {
    expect(paint(mailbox([])).some((b) => b !== 0)).toBe(true)
  })
})
