import { describe, expect, test } from "bun:test"
import { Scene } from "../kit/draw"
import { clipLabel, drawClipboard, drawMachine, inboxSections, phoneBar, ringFrame } from "../kit/surfaces"

describe("the phone in the top bar", () => {
  test("nothing owed is no segment at all", () => {
    expect(phoneBar({ phone: 0 })).toBeNull()
  })
  test("an answer owed is the one count, ringing", () => {
    expect(phoneBar({ phone: 3 })).toEqual({ text: "3 waiting on you", ringing: true })
  })
  test("ringing changes the glyph, so it is never colour alone; quiet holds still", () => {
    expect(new Set([0, 1, 2, 3].map((t) => ringFrame(t, true))).size).toBeGreaterThanOrEqual(2)
    expect(new Set([0, 1, 2, 3].map((t) => ringFrame(t, false))).size).toBe(1)
  })
})

describe("the answering machine and the sheriff's clipboard, drawn", () => {
  const paint = (tick: number, draw: (sc: Scene) => void) => {
    const sc = new Scene(60, 60, tick)
    draw(sc)
    sc.finish()
    return { rgba: Buffer.from(sc.cv.rgba), hits: sc.hits }
  }
  // the light is on for f % 4 < 2 (f = tick / 4): tick 0 lit, tick 8 dark
  test("the machine's light blinks while it holds messages, and says how many", () => {
    const lit = paint(0, (sc) => drawMachine(sc, 20, 40, 2)), dark = paint(8, (sc) => drawMachine(sc, 20, 40, 2))
    expect(lit.rgba.equals(dark.rgba)).toBe(false)
    expect(lit.hits).toEqual([expect.objectContaining({ tip: "the answering machine: 2 new messages", act: { kind: "machine" } })])
  })
  test("an empty machine never blinks", () => {
    expect(paint(0, (sc) => drawMachine(sc, 20, 40, 0)).rgba.equals(paint(8, (sc) => drawMachine(sc, 20, 40, 0)).rgba)).toBe(true)
  })
  test("the clipboard with rows looks different from a bare one; its tip lists who has each and what tracks it", () => {
    const rows = [{ owner: "cruz", tracking: "fix-sink", title: "the sink leaks" }, { owner: null, tracking: null, title: "a stray" }]
    const full = paint(0, (sc) => drawClipboard(sc, 20, 40, rows)), bare = paint(0, (sc) => drawClipboard(sc, 20, 40, []))
    expect(full.rgba.equals(bare.rgba)).toBe(false)
    expect(full.hits[0]!.act).toEqual({ kind: "clipboard" })
    expect(full.hits[0]!.tip).toContain("2 on the clipboard")
    expect(full.hits[0]!.tip).toContain("cruz · fix-sink · the sink leaks")
    expect(full.hits[0]!.tip).toContain("nobody · untracked · a stray")
  })
})

describe("the inbox by surface", () => {
  const n = (key: string, more: object = {}) => ({ key, title: key, ...more })
  test("sections run phone, machine, clipboard, and only the ones with something in them", () => {
    const s = inboxSections({ phone: [n("a")], machine: [], clipboard: [n("c")] })
    expect(s.map((x) => [x.label, x.items.map((i) => i.key)])).toEqual([["PHONE · 1", ["a"]], ["CLIPBOARD · 1", ["c"]]])
  })
  test("Uqbar's settled digest sits with the machine; what waits with Uqbar comes last", () => {
    const s = inboxSections({ phone: [n("a")], machine: [n("m")], clipboard: [n("c")], settled: [n("s")], uqbar: [n("u"), n("v")] })
    expect(s.map((x) => [x.surface, x.label])).toEqual([
      ["phone", "PHONE · 1"], ["machine", "MACHINE · 1"], ["settled", "SETTLED BY UQBAR · 1"], ["clipboard", "CLIPBOARD · 1"], ["uqbar", "WITH UQBAR · 2"],
    ])
  })
  test("a clipboard row says who has it and what tracks it, or that nobody does", () => {
    expect(clipLabel({ owner: "cruz", tracking: "fix-sink" })).toBe("cruz · fix-sink")
    expect(clipLabel({})).toBe("nobody · untracked")
  })
})
