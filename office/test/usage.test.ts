import { expect, test } from "bun:test"
import { usageHeader } from "../kit/usage"
import { EMPTY, type Agents } from "../kit/types"

const now = Date.parse("2026-10-13T16:50:00Z")
const at = (minsAgo: number) => new Date(now - minsAgo * 60_000).toISOString()
const office = (claude: NonNullable<Agents["usage"]>["claude"] | undefined): Agents => ({ ...EMPTY, ok: true, ...(claude === undefined ? {} : { usage: { claude } }) })

test("the plan's two windows, the five-hour one with its reset", () => {
  const a = office({ five_hour: { percent: 34, resets_at: "2026-10-13T19:00:00Z" }, seven_day: { percent: 44, resets_at: null }, at: at(2) })
  expect(usageHeader(a, now)).toEqual({ text: "claude 5h 34% (2h 10m) · wk 44%", hot: false })
})

test("a reading over half an hour old says how old; near a limit it runs hot", () => {
  const a = office({ five_hour: { percent: 86.5, resets_at: null }, seven_day: { percent: 51, resets_at: null }, at: at(47) })
  expect(usageHeader(a, now)).toEqual({ text: "claude 5h 87% · wk 51% · 47m old", hot: true })
  expect(usageHeader(office({ seven_day: { percent: 92, resets_at: null }, at: at(1) }), now)).toEqual({ text: "claude wk 92%", hot: true })
})

test("no reading yet says so, never a made-up zero; a server too old to send one shows nothing", () => {
  expect(usageHeader(office(null), now)).toEqual({ text: "claude: no reading yet", hot: false })
  expect(usageHeader(office(undefined), now)).toBeNull()
})

test("a window past its reset is dropped, not shown as its old figure at 0m", () => {
  const a = office({ five_hour: { percent: 34, resets_at: at(5) }, seven_day: { percent: 44, resets_at: null }, at: at(1) })
  expect(usageHeader(a, now)).toEqual({ text: "claude wk 44%", hot: false })
  expect(usageHeader(office({ five_hour: { percent: 95, resets_at: at(1) }, at: at(1) }), now)).toEqual({ text: "claude: no reading yet", hot: false })
})
