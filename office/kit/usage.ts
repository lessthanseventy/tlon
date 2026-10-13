import type { Agents, UsageWindow } from "./types"

const HOT_5H = 80, HOT_WEEK = 90, STALE_MIN = 30

const span = (ms: number) => {
  const m = Math.max(0, Math.round(ms / 60_000))
  return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${m % 60}m`
}

/** The Claude plan's meter for the header: `claude 5h 34% (2h 10m) · wk 44%`, its age once the reading
 * is over half an hour old, hot near a limit; null where the server sends no usage at all. */
export function usageHeader(a: Agents, now: number): { text: string; hot: boolean } | null {
  if (!a.usage) return null
  const c = a.usage.claude
  // a window past its reset says nothing about now: its figure was for the window before
  const live = (w?: UsageWindow) => (w && (!w.resets_at || Date.parse(w.resets_at) > now) ? w : undefined)
  const five = live(c?.five_hour), week = live(c?.seven_day)
  if (!c || (!five && !week)) return { text: "claude: no reading yet", hot: false }
  const parts: string[] = []
  if (five) parts.push(`5h ${Math.round(five.percent)}%${five.resets_at ? ` (${span(Date.parse(five.resets_at) - now)})` : ""}`)
  if (week) parts.push(`wk ${Math.round(week.percent)}%`)
  const age = now - Date.parse(c.at)
  if (age > STALE_MIN * 60_000) parts.push(`${span(age)} old`)
  const hot = (five?.percent ?? 0) >= HOT_5H || (week?.percent ?? 0) >= HOT_WEEK
  return { text: `claude ${parts.join(" · ")}`, hot }
}
