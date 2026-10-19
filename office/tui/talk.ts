// Talking in the office: what `m` (to a person) and `'` (to the office) post, and where.
import * as data from "./data"
import type { Thread } from "../kit/types"
import { studyOf } from "../kit/uqbar"

/** the workspace's lobby — its standing thread (shown as "the front desk"), where the manager hears the office and a coworker's desk (their home window) lives */
export const lobbyOf = (threads: Thread[], ws: number | null): number | null =>
  threads.find((t) => t.standing && t.workspace_id === ws)?.id ?? null

/** the body to post: `@name …` to a person, the bare words to the office; null when nothing was said */
export function speech(to: string | null, text: string): string | null {
  const s = text.trim()
  return s ? (to ? `@${to} ${s}` : s) : null
}

/** say it on the workspace's lobby (to uqbar, on its study, which wakes it); the status line's text */
export async function say(threads: Thread[], ws: number | null, to: string | null, text: string): Promise<string> {
  const study = to === "uqbar" ? studyOf(threads, ws) : null
  if (study !== null) {
    if (!text.trim()) return "nothing said"
    const r = await data.post(study, text.trim())
    return r.startsWith("sent") ? "said to uqbar" : r
  }
  const body = speech(to, text), lobby = lobbyOf(threads, ws)
  if (!body) return "nothing said"
  if (lobby === null) return "no front desk in this workspace to say it on"
  const r = await data.post(lobby, body)
  return r.startsWith("sent") ? (to ? `said to ${to}` : "said to the office") : r
}

/** hand thread `tid` to uqbar: a line on its study naming it, which wakes it; the status line's text */
export async function handToUqbar(threads: Thread[], ws: number | null, tid: number): Promise<string> {
  const study = studyOf(threads, ws), t = threads.find((x) => x.id === tid)
  if (study === null) return "uqbar has no study yet: the server opens it at boot"
  const r = await data.post(study, `Over to you: #${tid}${t ? ` ${t.title}` : ""}. See it through, and say here what you did.`)
  return r.startsWith("sent") ? `handed #${tid} to uqbar` : r
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

/** the lobby's posts that are a conversation with `x`: theirs, and the operator's that mention or answer them. A filter, no DM schema. */
export function conversation<M extends { id: number; author: string; body: string; reply_to?: number | null }>(msgs: M[], x: string, operator: string): M[] {
  const theirs = new Set(msgs.filter((m) => m.author === x).map((m) => m.id))
  const named = new RegExp(`@${x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![\\w-])`)
  return msgs.filter((m) => m.author === x || (m.author === operator && (named.test(m.body) || (m.reply_to != null && theirs.has(m.reply_to)))))
}
