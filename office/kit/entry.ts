// The entry (U): the office folded into a page — an encyclopedia article on the office as it is
// right now. A pure read of the snapshot + the needs list + today's activity feed; it holds no
// state of its own. counts come straight from `boardColumns` so they can never disagree with the
// board, and every footnote carries an `Act` — a key that opens its thread, list or issue.
import { boardColumns, COLS, type Act, type BoardCtx, type BoardItem } from "./crew"
import type { Agents } from "./types"

/** one thing waiting on the operator (a sliver of `Server.Office.Needs`) */
export type EntryNeed = { kind: string; level: "blocking" | "decide"; thread_id: number | null; title: string; at: string }
/** one row of the in-tray feed (a sliver of `Server.Office.Room.activity`) */
export type EntryEvent = { kind: string; at: string; thread_id: number | null; who: string | null; text: string }

export type Footnote = { mark: string; text: string; act: Act }
export type PivotCell = { count: number; wait: string | null }
export type PivotRow = { cow: string; cells: PivotCell[]; total: number }
export type EntryLine = { text: string; act: Act | null }
export type EntrySection = { label: string; lines: EntryLine[] }
export type Entry = {
  title: string
  prose: string
  counts: Record<string, number>
  pivot: { stages: string[]; rows: PivotRow[] }
  sections: EntrySection[]
  footnotes: Footnote[]
  diary: EntryLine[]
}

const SUP = "⁰¹²³⁴⁵⁶⁷⁸⁹"
const sup = (n: number) => String(n).split("").map((d) => SUP[Number(d)]!).join("")
const mark = (i: number) => sup(i + 1)

const ago = (at: string, now: Date): string => {
  const s = Math.max(0, Math.floor((now.getTime() - new Date(at).getTime()) / 1000))
  if (s < 60) return "now"
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86400) return `${Math.floor(s / 3600)}h`
  return `${Math.floor(s / 86400)}d`
}

const sameDay = (at: string, now: Date): boolean => {
  const d = new Date(at), n = now
  return d.getUTCFullYear() === n.getUTCFullYear() && d.getUTCMonth() === n.getUTCMonth() && d.getUTCDate() === n.getUTCDate()
}

const thread = (tid: number | null): Act | null => (tid != null ? { kind: "thread", tid } : null)

/** the entry — `a` is the workspace view (what the board shows), `feed` newest first */
export function entryOf(a: Agents, ctx: BoardCtx, needs: EntryNeed[], feed: EntryEvent[], now: Date): Entry {
  const cols = boardColumns(a, ctx)
  const counts = Object.fromEntries(cols.map((c) => [c.name, c.items.length]))

  // footnotes: each thread waiting on you opens its own thread, then the lists open their views
  const footnotes: Footnote[] = []
  for (const it of cols.flatMap((c) => c.items)) {
    if (it.asks && it.act.kind === "thread") footnotes.push({ mark: "", text: `#${it.act.tid} ${it.title} waits on you`, act: { kind: "thread", tid: it.act.tid } })
  }
  const shipped = feed.filter((e) => e.kind === "work_landed" && sameDay(e.at, now))
  if (needs.length) footnotes.push({ mark: "", text: "the inbox — what waits on you", act: { kind: "needs" } })
  if (shipped.length) footnotes.push({ mark: "", text: "shipped today", act: { kind: "tray" } })
  const stuck = a.triage ? Object.values(a.triage).reduce((n, c) => n + c, 0) : 0
  if (stuck) footnotes.push({ mark: "", text: "known problems — the sheriff's beat", act: { kind: "beacon" } })
  if (a.health?.state === "warn" && a.health.problems.length) footnotes.push({ mark: "", text: "the rack — what is not owned", act: { kind: "rack" } })
  footnotes.forEach((f, i) => (f.mark = mark(i)))
  const markOf = (kind: Act["kind"]) => footnotes.find((f) => f.act.kind === kind)?.mark ?? ""
  const waiting = footnotes.filter((f) => f.act.kind === "thread")
  const waitingMarks = waiting.map((f) => f.mark).join("")

  // the stage × coworker pivot: TICKETS has no owner, so it is prose only
  const stages = COLS.slice(1) // DOING SPEC PLAN BUILD REVIEW
  const rows: PivotRow[] = a.bench.map((c) => {
    const cells = stages.map((_st, i) => cellOf(cols[i + 1]!.items, c.name, feed, now))
    return { cow: c.name, cells, total: cells.reduce((n, x) => n + x.count, 0) }
  })

  const sections: EntrySection[] = [
    section("WAITING ON YOU", needs.map((n) => ({ text: `${n.kind} #${n.thread_id ?? "?"} ${n.title}`, act: thread(n.thread_id) }))),
    section("SHIPPED TODAY", shipped.map((e) => ({ text: e.text, act: thread(e.thread_id) }))),
    section("KNOWN PROBLEMS", [
      ...(stuck ? [{ text: `${stuck} stuck — blockers, failed checks, unled`, act: { kind: "beacon" } as Act }] : []),
      ...(a.health?.state === "warn" ? a.health.problems.map((p) => ({ text: p, act: { kind: "rack" } as Act })) : []),
    ]),
  ].filter((s) => s.lines.length > 0)

  const diary = feed.filter((e) => e.who === "uqbar" && sameDay(e.at, now)).map((e) => ({ text: e.text, act: thread(e.thread_id) }))

  const works = counts.DOING + counts.SPEC + counts.PLAN + counts.BUILD + counts.REVIEW
  const waits = waiting.length ? ` (${waiting.length} waiting on you${waitingMarks}${markOf("needs")})` : ""
  const prose =
    `${works} works in hand: ${counts.BUILD} at build, ${counts.REVIEW} at review${waits}, ${counts.DOING} doing. ` +
    `${shipped.length} shipped since this morning${markOf("tray")}. ` +
    `${stuck} known and owned${markOf("beacon")}; ${a.health?.problems.length ?? 0} not${markOf("rack")}.`

  return { title: "The Office, today", prose, counts, pivot: { stages, rows }, sections, footnotes, diary }
}

const cellOf = (items: BoardItem[], cow: string, feed: EntryEvent[], now: Date): PivotCell => {
  const here = items.filter((it) => it.who === cow)
  const waiting = here.filter((it) => (it.state?.kind === "needs" || it.state?.kind === "parked") && it.act.kind === "thread")
  const times = waiting.flatMap((it) => feed.filter((e) => e.thread_id === (it.act as { tid: number }).tid).map((e) => e.at)).sort()
  return { count: here.length, wait: times.length ? ago(times[0]!, now) : null }
}

const section = (label: string, lines: EntryLine[]): EntrySection => ({ label, lines })