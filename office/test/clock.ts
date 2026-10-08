// The gate runs the suite at fixed hours of today (OFFICE_TEST_HOUR — the small hours and midday):
// a test that reads the real clock gives one answer whenever it runs, not one per time of day.
import { setSystemTime } from "bun:test"

const hour = process.env.OFFICE_TEST_HOUR
if (hour !== undefined) {
  const at = new Date()
  at.setHours(Number(hour), 0, 0, 0)
  setSystemTime(at)
}
