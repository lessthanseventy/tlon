import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { viewOf } from "../kit/crew"
import { DEFAULT, resolve, setPreset } from "../kit/whimsy"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

// the one rule at every setting: chaos lives in the room, never in threads, tickets, turns or code
describe("whimsy never touches the work", () => {
  test("the dial, the sim, the events and the rooms import no data layer and call nothing out", () => {
    for (const f of ["kit/whimsy.ts", "kit/events.ts", "kit/sim.ts", "rooms/wide.ts", "rooms/rail.ts", "tui/whimsy-card.ts"]) {
      const src = readFileSync(new URL(`../${f}`, import.meta.url), "utf8")
      expect(src, f).not.toMatch(/from\s+["'][./]*(tui\/)?data["']/)
      expect(src, f).not.toMatch(/\bfetch\(|data\.(send|post|settingsEdit|did)\b/)
    }
    // the file layer touches the config dir only
    const file = readFileSync(new URL("../kit/whimsy-file.ts", import.meta.url), "utf8")
    expect(file).not.toMatch(/from\s+["'][./]*(tui\/)?data["']/)
  })
  test("rimworld, running, leaves the snapshot it was given exactly as it was", () => seeded(21, () => {
    const r = new WideRoom(696), a = viewOf(office(4), 1), before = structuredClone(a)
    ;(r as any).hour = () => 12
    r.setWhimsy(resolve(setPreset(DEFAULT, "rimworld")))
    for (let i = 0; i < 20_000; i++) r.step(a)
    for (const n of (r as any).actors.keys()) r.sourMood(n)
    for (let i = 0; i < 2_000; i++) r.step(a)
    expect(a).toEqual(before)
  }), 30_000)
})
