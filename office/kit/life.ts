// The life side as the office draws it: pure views over the snapshot's `life` block (Server.Life).
import type { Agents } from "./types"

/** level L starts at 100·L² xp (the server's curve); the bar only draws progress, never decides a level */
const levelStart = (level: number) => 100 * level * level

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
