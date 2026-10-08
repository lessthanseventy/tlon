// The life side as the office draws it: pure views over the snapshot's `life` block (Server.Life).
import type { Agents, LifeStatus } from "./types"

/** level L starts at 100·L² xp (the server's curve); the bar only draws progress, never decides a level */
const levelStart = (level: number) => 100 * level * level

/** the highest level among the home workspaces, null where there is no life side */
export const homeLevel = (a: Agents): number | null => {
  const levels = Object.values(a.life ?? {}).map((l) => l.level)
  return levels.length ? Math.max(...levels) : null
}

/** five cells for the way from `start` to `next` xp */
export function lifeBar(xp: number, start: number, next: number): string {
  const f = next > start ? Math.min(1, Math.max(0, (xp - start) / (next - start))) : 0
  const n = Math.min(5, Math.floor(f * 5))
  return "▰".repeat(n) + "▱".repeat(5 - n)
}

/** `lv 7 ▰▰▰▱▱ · 3 due`, or null where the workspace has no life side */
export function lifeHeader(a: Agents, ws: number | null): string | null {
  const l = ws === null ? undefined : a.life?.[String(ws)]
  if (!l) return null
  const start = levelStart(l.level), next = levelStart(l.level + 1)
  return `lv ${l.level} ${lifeBar(l.xp, start, next)} · ${l.due.length ? `${l.due.length} due` : "all done"}`
}

export type LifeRow = { kind: "routine" | "quest"; id: number; title: string; text: string }
const left = (s: number) => (s < 0 ? "overdue" : s < 3600 ? `${Math.ceil(s / 60)}m left` : `${Math.floor(s / 3600)}h left`)

/** the card's rows: due routines (overdue first, then soonest), then open quests */
export function lifeRows(s: LifeStatus): LifeRow[] {
  const due = [...s.due].sort((a, b) => a.window_remaining - b.window_remaining).map((d): LifeRow => {
    const streak = s.streaks[String(d.routine_id)] ?? 0
    return { kind: "routine", id: d.routine_id, title: d.title, text: `${d.title} · ${left(d.window_remaining)}${streak ? ` · streak ${streak}` : ""}` }
  })
  return [...due, ...s.quests.map((q): LifeRow => ({ kind: "quest", id: q.id, title: q.title, text: `${q.title} · +${q.xp} xp` }))]
}
