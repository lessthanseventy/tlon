import { expect, test } from "bun:test"
import { weekTrend } from "../kit/crew"

test("the TICKETS head says whether the pile grew or shrank this week, and nothing when flat or unknown", () => {
  expect(weekTrend({ ticket_week: { "1": { opened: 44, closed: 29 } } })).toBe("+15/wk")
  expect(weekTrend({ ticket_week: { "1": { opened: 3, closed: 7 } } })).toBe("-4/wk")
  expect(weekTrend({ ticket_week: { "1": { opened: 5, closed: 5 } } })).toBe("")
  expect(weekTrend({})).toBe("")
})
