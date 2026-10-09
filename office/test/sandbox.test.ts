import { expect, test } from "bun:test"
import { toy } from "../tui/sandbox"

test("the world is a full, ok snapshot with no server", () => {
  const t = toy(), a = t.snapshot()
  expect(a.ok).toBe(true)
  expect(a.bench.map((c) => c.name)).toContain("scharlach")
  expect(a.threads.length).toBeGreaterThanOrEqual(3)
  expect(a.roster.every((s) => a.bench.some((c) => c.name === s.agent))).toBe(true)
  expect(a.weather).not.toBeNull()
})
test("w steps the weather round the ring", () => {
  const t = toy(), seen = new Set([t.snapshot().weather!.kind])
  for (let i = 0; i < 7; i++) { t.nextWeather(); seen.add(t.snapshot().weather!.kind) }
  expect(seen.size).toBe(7)
})
test("a call-over is a fresh consult visit from one coworker to another", () => {
  const t = toy()
  t.callOver("yu"); const v = t.snapshot().visits
  expect(v).toHaveLength(1)
  expect(v[0]!.to).toBe("yu"); expect(v[0]!.from).not.toBe("yu")
  expect(Date.now() - Date.parse(v[0]!.at)).toBeLessThan(1000)
})
test("night toggles a clock override", () => {
  const t = toy()
  expect(t.now().getHours()).toBe(new Date().getHours())
  t.toggleNight(); expect(t.now().getHours()).toBe(23)
  t.toggleNight(); expect(t.now().getHours()).toBe(new Date().getHours())
})
