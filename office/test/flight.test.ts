import { expect, test } from "bun:test"
import { oneInFlight } from "../tui/flight"

// one refresh in flight; a call during it — a write's follow-up — waits for one more run, so it
// reads what was written, and any number of calls during a flight queue only that one
test("a call during a flight runs once more after it, and resolves after that re-read", async () => {
  let runs = 0, release: () => void = () => {}
  const f = oneInFlight(() => new Promise<void>((done) => { runs++; release = done }))
  const first = f()
  const after = [f(), f(), f()]
  expect(runs).toBe(1)
  let settled = false
  void Promise.all(after).then(() => { settled = true })
  release(); await first
  await Bun.sleep(0)
  expect(runs).toBe(2)
  expect(settled).toBe(false)
  release(); await Promise.all(after)
  expect(runs).toBe(2)
})
