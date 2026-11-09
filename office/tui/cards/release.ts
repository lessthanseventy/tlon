import { type Act } from "../../kit/crew"
import { entryOf } from "../../kit/entry"
import { queueItems, type QueueItem } from "../../kit/rack"
import { ROLE } from "../../kit/palette"
import { type Agents } from "../../kit/types"
import { studyOf } from "../../kit/uqbar"
import { bind } from "../keys"
import { type Row, type Action, type Card } from "../state"
import { boardCtx, waiting } from "../select"
import { dim, key, pink, plain, tidSeg } from "../ui"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function healthCard(app: State, ctl: Ctl): Card {
  if (!app.rack) return { title: "THE RACK", rows: [{ segs: [waiting(app, "probing…")] }], actions: [ctl.back1] }
  const ok = (b: boolean, s: string): Row => ({ segs: [{ s: b ? "● " : "✕ ", fg: b ? ROLE.live : ROLE.alarm }, plain(s)] })
  const up = app.rack.up_s < 3600 ? `${Math.floor(app.rack.up_s / 60)}m` : app.rack.up_s < 86400 ? `${Math.floor(app.rack.up_s / 3600)}h` : `${Math.floor(app.rack.up_s / 86400)}d`
  const queue = queueItems(app.rack, app.settings?.restart_pending ?? false)
  const queueRow = (q: QueueItem): Row => {
    const t = q.thread_id
    const mark = q.kind === "check" || q.kind === "gate" ? { s: "▶ ", fg: ROLE.live } : q.kind === "restart" ? { s: "↻ ", fg: ROLE.attention } : q.kind === "car" ? dim(`   ${q.pos} `) : { s: "⧗ ", fg: ROLE.inactive }
    return { segs: [mark, ...(t ? [tidSeg(t)] : []), plain(q.text), ...(q.kind === "car" && q.lead ? [dim(" (lead)")] : [])], ...(t ? { open: () => ctl.goThread(t, null) } : {}) }
  }
  const rows: Row[] = [
    ...app.rack.problems.map((p) => ({ segs: [pink("! "), plain(p)] })),
    ok(true, `tlon ${app.rack.version}, up ${up}`), ok(app.rack.db, "the database answers"), app.rack.jobs ? ok(true, "the job queue runs (staffing, sweeps, schedules)") : { segs: [dim("○ no job queue on this node")] },
    ok(app.rack.failed_jobs === 0, `${app.rack.failed_jobs} failed job(s) today`), ok(app.rack.tmux, "tmux is there for the coworkers"),
    { segs: [dim(`disk ${app.rack.disk_pct ?? "?"}% · memory ${app.rack.mem_pct ?? "?"}% · load ${app.rack.load ?? "?"}`)] },
    { segs: [plain("")] },
    { segs: [key("LANDING & CHECKS"), dim("  one full check at a time")] },
    ...(queue.length ? queue.map(queueRow) : [{ segs: [dim("  idle")] } as Row]),
  ]
  return { title: `THE RACK · ${app.rack.state === "ok" ? "all green" : "needs a look"}`, rows, actions: [ctl.back1] }
}

export function entryCard(app: State, ctl: Ctl, a: Agents): Card {
  const e = entryOf(a, boardCtx(app), app.needs, app.feed, new Date())
  const row = (text: string, x: Act | null): Row => ({ segs: [plain(text)], open: x ? () => ctl.act(x) : undefined })
  // Uqbar lives on its study: where it is now, and the verbs that reach it there
  const study = studyOf(app.all.threads, app.ws), me = app.all.roster.find((r) => r.agent === "uqbar")
  const where = !me ? "not in the office yet: its pane opens on the next word to it" : me.thinking ? `working${me.doing ? `: ${me.doing}` : ""}` : me.warm ? "at the shelf, between check-ins" : "asleep: the next word to it wakes a fresh one"
  const rows: Row[] = [{ segs: [{ s: "UQBAR ", fg: ROLE.attention }, plain(where)] }]
  for (const s of e.prose.split(". ").filter(Boolean)) rows.push({ segs: [plain(s.endsWith(".") ? s : s + ".")] })
  if (e.pivot.rows.length) {
    rows.push({ segs: [{ s: "stage × coworker", fg: ROLE.attention }] })
    rows.push({ segs: [dim(`coworker  ${e.pivot.stages.map((s) => s.toLowerCase()).join("  ")}`)] })
    for (const r of e.pivot.rows) {
      const cells = r.cells.map((c, i) => c.count ? `${e.pivot.stages[i]!.toLowerCase()} ${c.count}${c.wait ? ` ${c.wait}` : ""}` : "·").join("  ")
      rows.push({ segs: [{ s: r.cow, fg: ROLE.key }, plain(`  ${cells}  (${r.total})`)] })
    }
  }
  for (const s of e.sections) {
    rows.push({ segs: [{ s: s.label, fg: ROLE.attention }] })
    for (const l of s.lines) rows.push(row(l.text, l.act))
  }
  if (e.diary.length) { rows.push({ segs: [{ s: "WHAT UQBAR DID TODAY", fg: ROLE.attention }] }); for (const d of e.diary) rows.push(row(d.text, d.act)) }
  if (e.footnotes.length) { rows.push({ segs: [{ s: "FOOTNOTES", fg: ROLE.attention }] }); for (const f of e.footnotes) rows.push(row(`${f.mark} ${f.text}`, f.act)) }
  const verbs: Action[] = study === null ? [] : [
    { ...bind("entry.m"), run: () => ctl.talk("uqbar") },
    { ...bind("entry.t"), run: () => void ctl.zoomInto(study) },
    { ...bind("entry.v"), run: () => ctl.openReader(study) },
  ]
  const notes: Action[] = e.footnotes.slice(0, 9).map((f, i) => ({ key: String(i + 1), label: `footnote ${f.mark} — ${f.text}`, run: () => ctl.act(f.act) }))
  return { title: e.title, tint: ROLE.inactive, rows, actions: [...verbs, ...notes, ctl.back1] }
}
