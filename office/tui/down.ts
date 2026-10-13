// The header's line for a down channel: how old the held view is and the verb that brings it back.
import type { Agents } from "../kit/types"

const age = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000))
  return s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h`
}

/** null while the channel is up */
export function downHeader(a: Agents, now: number): string | null {
  if (a.ok) return null
  const held = a.heldAt === undefined ? "" : ` · as of ${age(now - a.heldAt)} ago`
  return `${a.note ?? "channel down"}${held} · mise run server:restart`
}
