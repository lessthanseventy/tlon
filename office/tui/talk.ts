// Talking in the office: what `m` (to a person) and `'` (to the office) post, and where.
import * as data from "./data"
import type { Thread } from "../kit/types"

/** the workspace's lobby — its standing thread, where the manager hears the office and a home window lives */
export const lobbyOf = (threads: Thread[], ws: number | null): number | null =>
  threads.find((t) => t.standing && t.workspace_id === ws)?.id ?? null

/** the body to post: `@name …` to a person, the bare words to the office; null when nothing was said */
export function speech(to: string | null, text: string): string | null {
  const s = text.trim()
  return s ? (to ? `@${to} ${s}` : s) : null
}

/** say it on the workspace's lobby; the status line's text */
export async function say(threads: Thread[], ws: number | null, to: string | null, text: string): Promise<string> {
  const body = speech(to, text), lobby = lobbyOf(threads, ws)
  if (!body) return "nothing said"
  if (lobby === null) return "no lobby in this workspace to say it on"
  const r = await data.post(lobby, body)
  return r.startsWith("sent") ? (to ? `said to ${to}` : "said to the office") : r
}
