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

type Said = { id: number; author: string; body: string; kind?: string; reply_to?: number | null }

/**
 * the lobby's posts answering the operator: a reply to one of their posts, or X's next post after an operator `@X`.
 * Only the page `data.thread` returns is seen, so a reply to an operator post that scrolled out of it is missed.
 */
export function replies(msgs: Said[], operator: string): { id: number; agent: string; line: string }[] {
  const mine = new Set<number>(), out: { id: number; agent: string; line: string }[] = []
  let asked = new Set<string>()
  for (const m of msgs) {
    if (m.author === operator) {
      mine.add(m.id)
      asked = new Set([...m.body.matchAll(/@([\w-]+)/g)].map((x) => x[1]!))
    } else if (m.author !== "tlon" && ((m.reply_to != null && mine.has(m.reply_to)) || asked.has(m.author))) {
      asked.delete(m.author)
      out.push({ id: m.id, agent: m.author, line: m.body })
    }
  }
  return out
}
