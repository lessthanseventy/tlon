// Scharlach, the sheriff — the office's Dwight (office-as-a-toy design §2). He enforces the rules,
// and enjoys it too much: a nameplate he partly gave himself, a mug he bought himself, and a demerit
// ledger on his desk that ticks up when a coworker's build goes red. Nobody knows what demerits are
// for. He does.
//
// The ledger is presentation only: it ticks from a red-build signal the office already sees, never
// touches a thread or a turn, and lives on the client.

export const SHERIFF = "scharlach"
export const NAMEPLATE = "Sheriff (Assistant to the Manager)"
export const MUG = "WORLD'S BEST SHERIFF"

/** the demerit ledger: one tally per coworker, plus the threads already ticked this red */
export type Ledger = { demerits: Map<string, number>; ticked: Set<number> }

export const newLedger = (): Ledger => ({ demerits: new Map(), ticked: new Set() })

/** the ledger as a card line: each coworker with demerits and their tally, or a clean bill */
export function ledgerLines(l: Ledger, bench: readonly { name: string }[]): string[] {
  const has = bench.map((c) => [c.name, demerits(l, c.name)] as const).filter(([, n]) => n > 0)
  if (!has.length) return ["demerits: none — the office is behaving. For now."]
  return ["demerits:", ...has.map(([name, n]) => `  ${name} ${n}`)]
}

/** how many demerits `agent` has on the ledger */
export const demerits = (l: Ledger, agent: string): number => l.demerits.get(agent) ?? 0

/** tick one demerit onto `agent`'s tally (returns a new ledger) */
export function tickRed(l: Ledger, agent: string): Ledger {
  const demerits = new Map(l.demerits)
  demerits.set(agent, (demerits.get(agent) ?? 0) + 1)
  return { demerits, ticked: l.ticked }
}

/**
 * Tick the ledger for each red thread's lead. A thread already ticked this red does not re-tick; a
 * thread whose red clears is forgotten, so a fresh red on it ticks again. `threads` maps a thread id
 * to its lead. Returns a new ledger.
 */
export function tickForRedThreads(l: Ledger, redIds: readonly number[], threads: { id: number; lead?: string | null }[]): Ledger {
  const byId = new Map(threads.map((t) => [t.id, t.lead]))
  let next = l
  const ticked = new Set<number>()
  for (const id of redIds) {
    if (l.ticked.has(id)) { ticked.add(id); continue }
    const lead = byId.get(id)
    if (lead) { next = tickRed(next, lead); ticked.add(id) }
  }
  return { demerits: next.demerits, ticked }
}