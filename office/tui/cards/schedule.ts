import { ROLE } from "../../kit/palette"
import { lifeRows } from "../../kit/life"
import * as data from "../data"
import { bind } from "../keys"
import { wrap } from "../editor"
import { type Seg } from "../term"
import { parseWhen, showWhen } from "../when"
import { type Mode, type Row, type Cycle, type Action, type Card } from "../state"
import { ago, cols, dim, key, plain, runGlyph, stamp } from "../ui"
import { view, waiting } from "../select"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export const KIND_OF: Record<data.ScheduleKind, string> = { agent: "agent", workline: "workline", script: "script" }

/** a schedule as one row: on or paused, what, when, next, how the last run went */
export function scheduleSegs(s: data.Schedule): Seg[] {
  const next = s.next_at ? (new Date(s.next_at).getTime() - Date.now() < 60_000 ? "now" : stamp(s.next_at)) : s.enabled ? "done" : "paused"
  return [
    { s: s.enabled ? "● " : "○ ", fg: s.enabled ? ROLE.live : ROLE.inactive }, dim(KIND_OF[s.kind].padEnd(9)), plain(s.title), dim(`  ${showWhen(s)}${s.agent ? ` · ${s.agent}` : ""}${s.standing ? " · standing" : ""}`),
    key(`  next ${next}`), ...(s.last ? [dim("  last "), runGlyph(s.last), dim(` ${ago(s.last.at)}`)] : []),
  ]
}

/** schedule something new, or change `edit`: what it does (with how), then when */
export function newSchedule(app: State, ctl: Ctl, edit?: data.Schedule) {
  if (app.ws === null) return
  const w = app.ws, bench = view(app).bench
  const kinds = [{ label: "an agent run", value: "agent" }, { label: "a workline", value: "workline" }, { label: "a script", value: "script" }]
  const threads = [{ label: "a fresh thread each time", value: false }, { label: "one standing thread", value: true }]
  const who = [{ label: "the workspace's lead", value: null }, ...bench.map((b) => ({ label: b.name, value: b.name }))]
  const cycles: Cycle[] = [
    ...(edit ? [] : [{ name: "run", values: kinds, i: 0 }]),
    { name: "in", values: threads, i: edit?.standing ? 1 : 0 },
    { name: "with (agent runs)", values: who, i: Math.max(0, who.findIndex((x) => x.value === (edit?.agent ?? null))) },
  ]
  ctl.ask(edit ? `${edit.title} — what it does` : "schedule — the prompt, the workline's first words, or the shell command", (body, picks) => {
    if (!body.trim()) return
    const [kind, standing, agent] = edit ? [edit.kind, ...picks] : picks
    ctl.ask("when — a cron (0 9 * * 1-5, @daily) or a time (14:30, 2026-10-06 14:30, in 2h)", (text) => {
      const when = parseWhen(text)
      if (!when) { app.status = "a schedule needs a when"; return ctl.draw() }
      const attrs = { body: body.trim(), standing: standing as boolean, agent: kind === "agent" ? (agent as string | null) : null, ...when }
      void ctl.did(edit ? data.schedulePatch(edit.id, attrs) : data.scheduleNew(w, { kind: kind as data.ScheduleKind, ...attrs })).then(ctl.loadCard).then(ctl.draw)
    }, { text: edit ? showWhen(edit) : "" })
  }, { multiline: true, text: edit?.body, cycles })
}

/** a new routine (title, then how often) */
export function newRoutine(app: State, ctl: Ctl) {
  if (app.ws === null) return
  const w = app.ws
  ctl.ask("routine — what", (title) => {
    if (!title.trim()) return
    ctl.ask("every — a cron (0 9 * * *) or @daily / @weekly", (every) => {
      if (every.trim()) void ctl.did(data.routineNew(w, title.trim(), every.trim())).then(ctl.loadCard).then(ctl.draw)
    })
  })
}

export function newQuest(app: State, ctl: Ctl) {
  if (app.ws === null) return
  const w = app.ws
  ctl.ask("quest — what", (title) => { if (title.trim()) void ctl.did(data.questNew(w, title.trim())).then(ctl.loadCard).then(ctl.draw) })
}

export function calendarCard(app: State, ctl: Ctl): Card {
  const now = new Date(), first = new Date(now.getFullYear(), now.getMonth(), 1).getDay(), days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
  const booked = new Set((app.cal ?? []).filter((s) => s.enabled).flatMap((s) => s.days))
  const rows: Row[] = [{ segs: [dim("  Su  Mo  Tu  We  Th  Fr  Sa")] }]
  let week: Seg[] = [plain("    ".repeat(first))]
  for (let d = 1; d <= days; d++) {
    const cell = String(d).padStart(3) + (booked.has(d) ? "•" : " ")
    week.push(d === now.getDate() ? { s: cell, fg: ROLE.attention, bold: true } : booked.has(d) ? key(cell) : d < now.getDate() ? dim(cell) : plain(cell))
    if ((first + d) % 7 === 0 || d === days) { rows.push({ segs: week }); week = [] }
  }
  if (!app.cal) rows.push({ segs: [waiting(app, "reading the schedule…")] })
  else if (!app.cal.length) rows.push({ segs: [dim("nothing scheduled yet")] })
  else {
    rows.push({ segs: [key(`SCHEDULED · ${app.cal.length}`)] })
    for (const s of app.cal) rows.push({ segs: scheduleSegs(s), open: () => ctl.open({ kind: "runs", id: s.id }), ref: s })
  }
  const s = rows[app.sel]?.ref as data.Schedule | undefined
  return {
    title: now.toLocaleString("en", { month: "long", year: "numeric" }).toUpperCase(), rows,
    actions: [
      { ...bind("calendar.n"), run: () => newSchedule(app, ctl) },
      ...(s ? [
        { ...bind("calendar.e"), run: () => newSchedule(app, ctl, s) },
        { ...bind("calendar.space", s.enabled ? "pause it" : "resume it"), run: () => void ctl.did(data.schedulePatch(s.id, { enabled: !s.enabled })).then(ctl.loadCard).then(ctl.draw) },
        { ...bind("calendar.r"), run: () => void ctl.did(data.scheduleRun(s.id)).then(ctl.loadCard).then(ctl.draw) },
        { ...bind("calendar.d"), run: () => ctl.ask2(`remove "${s.title}" and its runs`, () => void ctl.did(data.scheduleDelete(s.id)).then(ctl.loadCard).then(ctl.draw)) },
      ] : []),
      ctl.back1,
    ],
  }
}

export function lifeCard(app: State, ctl: Ctl): Card {
  const s = app.lifeCard
  const rows: Row[] = s ? lifeRows(s).map((r) => ({
    segs: [plain(r.text)],
    open: () => void ctl.did(r.kind === "routine" ? data.routineDone(r.id, r.title) : data.questDone(r.id, r.title)).then(ctl.loadCard).then(ctl.draw),
  })) : [{ segs: [waiting(app, "reading the day…")] }]
  if (s && !rows.length) rows.push({ segs: [dim("nothing due, no open quests")] })
  if (s) rows.unshift({ segs: [s.dump ? plain(`dump · ${data.lines(s.dump.lines)} · edited ${stamp(s.dump.updated_at)}`) : dim("dump · empty — ⏎ to pour it all out")], open: ctl.openDump })
  return {
    title: s ? `LIFE · lv ${s.level} · ${s.xp} xp` : "LIFE", rows,
    actions: [{ ...bind("life.E"), run: () => ctl.open({ kind: "pages" }) }, { ...bind("life.r"), run: () => newRoutine(app, ctl) }, { ...bind("life.Q"), run: () => newQuest(app, ctl) }, ctl.back1],
  }
}

export function pagesCard(app: State, ctl: Ctl): Card {
  const rows: Row[] = !app.dumpPages ? [{ segs: [waiting(app, "turning back the pages…")] }]
    : !app.dumpPages.length ? [{ segs: [dim("no earlier pages yet: every save keeps the one it replaced")] }]
    : app.dumpPages.map((p) => ({ segs: [dim(`${stamp(p.at)}  `), plain(data.lines(p.lines)), dim(`  ${p.first}`)], open: () => void ctl.readPage(p.id), ref: p }))
  const p = rows[app.sel]?.ref as data.DumpPage | undefined
  const up: Action = { ...bind("pages.esc"), run: () => ctl.open({ kind: "life" }) }
  return {
    title: "THE DUMP · EARLIER PAGES", rows,
    actions: [...(p ? [{ ...bind("pages.enter"), run: () => void ctl.readPage(p.id) }, { ...bind("pages.R"), run: () => ctl.ask2(`put back the ${stamp(p.at)} page (today's is kept as an earlier page)`, () => void ctl.restorePage(p.id)) }] : []), up],
  }
}

export function runsCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "runs" }>): Card {
  const id = mode.id, s = app.cal?.find((x) => x.id === id)
  const rows: Row[] = app.board.map((r) => ({
    segs: [runGlyph(r), dim(` ${stamp(r.started_at)} `), plain(r.status.padEnd(8)), dim(r.exit === null ? "" : `exit ${r.exit}  `), r.thread_id ? key(`→ #${r.thread_id}  `) : dim(""), dim((r.output ?? "").replace(/\s+/g, " ").slice(0, 80))],
    open: () => (r.thread_id && !r.output ? ctl.openReader(r.thread_id) : ctl.open({ kind: "run", id, run: r.id })),
    ref: r,
  }))
  return {
    title: `RUNS · ${s?.title ?? ""}`, rows: rows.length ? rows : [{ segs: [dim("it hasn't run yet")] }],
    actions: [{ ...bind("runs.r"), run: () => void ctl.did(data.scheduleRun(id)).then(ctl.loadCard).then(ctl.draw) }, { ...bind("runs.esc"), run: () => ctl.open({ kind: "calendar" }) }],
  }
}

export function runCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "run" }>): Card {
  const { id, run } = mode
  const r = app.board.find((x) => x.id === run)
  const up: Action = { ...bind("run.esc"), run: () => ctl.open({ kind: "runs", id }) }
  if (!r) return { title: "RUN", rows: [{ segs: [dim("gone")] }], actions: [up] }
  const rows: Row[] = [{ segs: [runGlyph(r), dim(` started ${stamp(r.started_at)}${r.finished_at ? `, finished ${stamp(r.finished_at)}` : ", still running"}`), ...(r.thread_id ? [key(`  → #${r.thread_id}`)] : [])] }]
  for (const l of wrap(r.output ?? "(no output)", cols() - 40)) rows.push({ segs: [plain(l)] })
  return { title: `RUN #${r.id} · ${r.status}${r.exit === null ? "" : ` · exit ${r.exit}`}`, rows, actions: [...(r.thread_id ? [{ ...bind("run.t"), run: () => ctl.openReader(r.thread_id!) }] : []), up] }
}
