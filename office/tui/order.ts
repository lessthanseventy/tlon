// How a list card orders what it shows: `s` steps its sort, `g` its grouping (the same keys on every
// card that has them). Pure, so the cards only say which modes they offer.
import type { Crew } from "../kit/crew"

export type Sort<T> = { name: string; cmp: (a: T, b: T) => number }
/** `label` heads a group; groups are shown in `rank` order (then by label) */
export type Group<T> = { name: string; label: (t: T) => string; rank?: (label: string) => number }

/** the mode after `cur` in `modes`, wrapping */
export const next = <T,>(modes: readonly T[], cur: T): T => modes[(modes.indexOf(cur) + 1) % modes.length]!

/** `items` sorted (stably) and, when grouped, split under their labels; ungrouped is one group with no label */
export function arrange<T>(items: T[], cmp: (a: T, b: T) => number, group: Group<T> | null): { label: string | null; items: T[] }[] {
  const sorted = [...items].sort(cmp)
  if (!group) return [{ label: null, items: sorted }]
  const by = new Map<string, T[]>()
  for (const t of sorted) by.set(group.label(t), [...(by.get(group.label(t)) ?? []), t])
  const rank = (l: string) => group.rank?.(l) ?? 0
  return [...by].sort(([a], [b]) => rank(a) - rank(b) || a.localeCompare(b)).map(([label, items]) => ({ label, items }))
}

const STATUS_RANK = { waiting: 0, working: 1, idle: 2 } as const
const STATUS_LABEL = { waiting: "waiting on you", working: "working", idle: "idle" } as const
const byName = (a: Crew, b: Crew) => a.name.localeCompare(b.name)

export const CREW_SORTS: Sort<Crew>[] = [
  { name: "bench", cmp: () => 0 },
  { name: "name", cmp: byName },
  { name: "status", cmp: (a, b) => STATUS_RANK[a.status] - STATUS_RANK[b.status] },
  { name: "thread", cmp: (a, b) => (a.thread ?? Infinity) - (b.thread ?? Infinity) },
]
const role = (c: Crew) => (c.manager ? "manager" : c.archetype ?? "?")
export const CREW_GROUPS: Group<Crew>[] = [
  { name: "role", label: role },
  { name: "status", label: (c) => STATUS_LABEL[c.status], rank: (l) => Object.values(STATUS_LABEL).indexOf(l as never) },
  { name: "thread", label: (c) => (c.thread === null ? "on the bench" : `#${c.thread}`), rank: (l) => (l.startsWith("#") ? Number(l.slice(1)) : Infinity) },
]
