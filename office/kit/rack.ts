import type { MergeItem } from "./types"

/** One LANDING & CHECKS list for the rack: what the machine is checking, who waits for it (in
 * ticket order, as the server sends them), the running landing gate as one block (its header with
 * the check it runs folded in, then its cars), who waits behind it, and a restart waiting for quiet.
 * All of it is status, never a Need. */
export type QueueItem = {
  kind: "check" | "wait" | "gate" | "car" | "next" | "restart"; text: string; thread_id?: number
  /** a car's place in its train, and whether it leads */
  pos?: number; lead?: boolean
}

type Queues = { checks?: { running: string | null; waiting: string[] }; merge_queue?: MergeItem[] }

const pidOf = (line: string) => Number(/\(pid (\d+)\)/.exec(line)?.[1] ?? NaN)

const age = (since: string | null | undefined, now: number) => {
  if (!since) return ""
  const m = Math.max(0, Math.floor((now - Date.parse(since)) / 60_000))
  return ` ${m < 60 ? `${m}m` : `${Math.floor(m / 60)}h${m % 60}m`}`
}

export function queueItems(h: Queues, restartPending: boolean, now = Date.now()): QueueItem[] {
  const merge = h.merge_queue ?? []
  const running = merge.find((m) => m.state === "landing")
  const gate = running ? running.gate ?? { pid: null, started_at: null } : null
  const carries = merge.filter((m) => m === running || (m.gate && typeof m.train === "object" && m.train))
  const owned = gate?.pid != null && h.checks?.running != null && pidOf(h.checks.running) === gate.pid
  const train = running && typeof running.train === "object" ? running.train : null
  const label = train?.split ? "landing → main  split: lead lands alone" : (train?.size ?? 1) > 1 ? "🚃 train → main" : "landing → main"
  return [
    ...(h.checks?.running && !owned ? [{ kind: "check" as const, text: h.checks.running }] : []),
    ...(h.checks?.waiting ?? []).map((text) => ({ kind: "wait" as const, text })),
    ...(gate ? [{ kind: "gate" as const, text: `${label}  gate running${age(gate.started_at, now)}${gate.pid != null ? ` · pid ${gate.pid}` : ""}` }] : []),
    ...carries.map((m) => {
      const pos = typeof m.train === "object" && m.train ? m.train.pos : 1
      return { kind: "car" as const, text: m.title, thread_id: m.thread_id, pos, lead: pos === 1 }
    }),
    ...merge.filter((m) => !carries.includes(m)).map((m) => ({
      kind: "next" as const, thread_id: m.thread_id,
      text: `${m.title} ${m.train === "solo" ? (m.title.startsWith("PR #") ? "(PR · lands solo)" : "(lands solo)") : "(own turn)"}`,
    })),
    ...(restartPending ? [{ kind: "restart" as const, text: "a restart is scheduled — it runs the moment nobody is mid-turn" }] : []),
  ]
}
