// "When" as you type it for a schedule: a cron (five fields, or @daily and kin) passes through for
// the server to check; a time (`14:30`, `2026-10-06 14:30`, `in 2h`, `in 45m`) is a one-off, read
// in your local time and sent as an instant.

export type When = { cron: string; at: null } | { cron: null; at: string }

export function parseWhen(input: string, now = new Date()): When | null {
  const s = input.trim()
  if (!s) return null
  let m: RegExpMatchArray | null
  if ((m = s.match(/^in\s+(\d+)\s*(m|min|mins|minutes?|h|hrs?|hours?|d|days?)$/i))) {
    const n = Number(m[1]), unit = m[2]![0]!.toLowerCase()
    return once(new Date(now.getTime() + n * (unit === "m" ? 60_000 : unit === "h" ? 3_600_000 : 86_400_000)))
  }
  if ((m = s.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})$/))) {
    return once(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5])))
  }
  if ((m = s.match(/^(\d{1,2}):(\d{2})$/))) {
    const t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), Number(m[1]), Number(m[2]))
    if (t <= now) t.setDate(t.getDate() + 1)
    return once(t)
  }
  return { cron: s, at: null }
}
const once = (d: Date): When => ({ cron: null, at: d.toISOString() })

/** a schedule's "when" back as you'd type it: its cron, or its time in local terms */
export function showWhen(w: { cron: string | null; at: string | null }): string {
  if (w.cron) return w.cron
  if (!w.at) return ""
  const d = new Date(w.at), p = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}
