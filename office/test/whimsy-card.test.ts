import { describe, expect, test } from "bun:test"
import { whimsyRows, whimsyTitle, resetToPreset } from "../tui/whimsy-card"
import { DEFAULT, isCustom, resolve, setDial, setPreset } from "../kit/whimsy"

const row = (s: Parameters<typeof whimsyRows>[0], label: string) => whimsyRows(s).find((r) => r.label === label)!

describe("the wackiness card", () => {
  test("the title names the preset, and says custom once a dial is touched", () => {
    expect(whimsyTitle(DEFAULT)).toBe("WACKINESS · casual")
    expect(whimsyTitle(setDial(DEFAULT, "banter", false))).toBe("WACKINESS · casual (custom)")
  })
  test("picking a preset row cycles presets and clears overrides", () => {
    const s = setDial(DEFAULT, "banter", false)
    const next = row(s, "preset").next(s)
    expect(next.preset).toBe("party")
    expect(isCustom(next)).toBe(false)
  })
  test("a dial row flips that one dial and the preset holds the rest", () => {
    const s = row(setPreset(DEFAULT, "rimworld"), "banter").next(setPreset(DEFAULT, "rimworld"))
    expect(resolve(s).banter).toBe(false)
    expect(resolve(s).chain).toBe(true)
    expect(isCustom(s)).toBe(true)
  })
  test("a switched-off event shows as one row off, the rest on", () => {
    const s = row(DEFAULT, "event: zoo").next(DEFAULT)
    const vals = Object.fromEntries(whimsyRows(s).filter((r) => r.label.startsWith("event: ")).map((r) => [r.label, r.value]))
    expect(vals["event: zoo"]).toBe("off")
    expect(Object.entries(vals).filter(([k]) => k !== "event: zoo").every(([, v]) => v === "on")).toBe(true)
  })
  test("0 puts the dials back to the preset", () => {
    expect(resetToPreset(setDial(setPreset(DEFAULT, "party"), "pets", false))).toEqual(setPreset(DEFAULT, "party"))
  })
  test("frequency and doorbell cycle through all their values and wrap", () => {
    let s = DEFAULT
    const seen = new Set<string>()
    for (let i = 0; i < 4; i++) { seen.add(row(s, "frequency").value); s = row(s, "frequency").next(s) }
    expect([...seen].sort()).toEqual(["lots", "never", "rare", "some"])
    expect(row(s, "frequency").value).toBe(row(DEFAULT, "frequency").value)
  })
})
