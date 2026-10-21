/** One LANDING & CHECKS list for the rack: what the machine is checking, who waits for it (in
 * ticket order, as the server sends them), what is landing, and a restart waiting for quiet. All of
 * it is status, never a Need. */
export type QueueItem = { kind: "check" | "wait" | "landing" | "queued" | "restart"; text: string; thread_id?: number }

type Queues = {
  checks?: { running: string | null; waiting: string[] }
  merge_queue?: { thread_id: number; title: string; state: "landing" | "queued" }[]
}

export function queueItems(h: Queues, restartPending: boolean): QueueItem[] {
  const merge = h.merge_queue ?? []
  return [
    ...(h.checks?.running ? [{ kind: "check" as const, text: h.checks.running }] : []),
    ...(h.checks?.waiting ?? []).map((text) => ({ kind: "wait" as const, text })),
    ...merge.filter((m) => m.state === "landing").map((m) => ({ kind: "landing" as const, text: m.title, thread_id: m.thread_id })),
    ...merge.filter((m) => m.state === "queued").map((m) => ({ kind: "queued" as const, text: m.title, thread_id: m.thread_id })),
    ...(restartPending ? [{ kind: "restart" as const, text: "a restart is scheduled — it runs the moment nobody is mid-turn" }] : []),
  ]
}
