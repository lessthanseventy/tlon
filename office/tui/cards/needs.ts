import { clipLabel, inboxSections } from "../../kit/surfaces"
import { ROLE } from "../../kit/palette"
import * as data from "../data"
import { bind } from "../keys"
import { wrap } from "../editor"
import { type Mode, type Row, type Action, type Card } from "../state"
import { ago, dim, key, live, oneLine, paneW, pink, plain, tidSeg } from "../ui"
import { waiting } from "../select"
import type { State } from "../state"
import type { Ctl } from "../ctl"

/** what a triage item is: its section, and so which actions it has */
export type StuckKind = "blocker" | "check" | "unled"

export function stuckActions(app: State, ctl: Ctl, s: data.Stuck, kind: StuckKind): Action[] {
  const after = () => { if (app.mode.kind === "issue" && !app.stuck?.blockers.shown.some((x) => x.issue_id === s.issue_id)) ctl.back(); ctl.draw() }
  const read: Action = { ...bind("need.v"), run: () => ctl.openReader(s.thread_id) }
  if (kind === "blocker" && s.issue_id !== undefined) {
    const id = s.issue_id, ticket = s.ticket_id
    return [
      // owned: the ticket is the fix in flight; the issue comes back to you to close when it is done
      ticket ? { ...bind("need.g.issue"), label: `open ticket #${ticket}`, run: () => ctl.open({ kind: "ticket", id: ticket }) } : { ...bind("need.g.issue"), run: () => void ctl.did(data.fixIssue(id)).then(after) },
      { ...bind("need.x.issue"), run: () => ctl.ask("resolve — why (naming the PR banks the sheriff's postmortem)", (r) => { if (r.trim()) void ctl.did(data.resolveIssue(id, r.trim())).then(after) }) },
      read,
    ]
  }
  if (kind === "check") return [...(s.stage === "verify" ? [{ ...bind("need.V.verify_failed"), run: () => void ctl.did(data.reverify(s.thread_id)).then(after) }] : []), read]
  return [{ ...bind("need.o.stalled"), run: () => ctl.ask(`hand #${s.thread_id} to — a coworker's name`, (r) => { if (r.trim()) void ctl.did(data.handOff(s.thread_id, r.trim())).then(after) }) }, read]
}

/** what a stalled need's nudge says to the lead */
export const NUDGE = "Nothing has moved here for a while: advance the stage if its work is done, or say what is blocking you."

/** answer with a note: a one-line box naming the options; its first word is an option's number, key or label, the rest goes on as typed — "<key> <note>", the form the server splits */
export function answerWithNote(app: State, ctl: Ctl, id: number, options: { key: string; label: string }[], after: () => void = () => {}) {
  const opts = options.slice(0, 9)
  ctl.ask(`answer with a note — ${opts.map((o, i) => `${i + 1} ${o.label}`).join(" · ")}`, (s) => {
    const m = s.trim().match(/^(\S+)\s*([\s\S]*)$/), w = m?.[1]?.toLowerCase() ?? ""
    const o = opts[Number(w) - 1] ?? opts.find((x) => x.key.toLowerCase() === w || x.label.toLowerCase() === w)
    if (!o) { app.status = "start with the option's number, key or label, then the note"; return ctl.draw() }
    void ctl.did(data.answer(id, m![2] ? `${o.key} ${m![2]}` : o.key)).then(after)
  })
}

/** what can be done about one waiting item — the inbox's list and its one-at-a-time card share these */
export function needActions(app: State, ctl: Ctl, n: data.Need): Action[] {
  const tid = n.thread_id ?? null
  const after = () => void ctl.refresh()
  // settled by Uqbar: overruling it is the one answer; it goes back to Uqbar, not to you
  if (n.route === "settled") return [{ ...bind("need.u.settled"), run: () => void ctl.did(data.overrule(n.key)).then(after) }, ...(tid ? [{ ...bind("need.v"), run: () => ctl.openReader(tid) }] : [])]
  const acts: Action[] = [
    ...(n.kind === "gate" && tid && !n.ref ? [{ ...bind("need.A.gate"), run: () => void ctl.did(data.approve(tid)).then(after) }] : []),
    ...(n.kind === "gate" && n.ref ? (n.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void ctl.did(data.answer(n.ref!, o.key)).then(after) })) : []),
    ...(n.kind === "ask" && n.ref ? (n.options ?? []).slice(0, 9).map((o): Action => ({ key: o.key, label: o.label, run: () => void ctl.did(data.answer(n.ref!, o.key)).then(after) })) : []),
    ...(n.kind === "ask" && n.ref && n.options?.length ? [{ ...bind("need.n.ask"), run: () => answerWithNote(app, ctl, n.ref!, n.options!, after) }] : []),
    ...(n.kind === "ask" && n.ref && n.ask !== "uqbar" ? [{ ...bind("need.u.ask"), run: () => void ctl.did(data.handToUqbar(n.ref!)).then(after) }] : []),
    ...(n.kind === "seats" && n.ref ? [{ ...bind("need.1.seats", `raise the cap to ${n.ref}`), run: () => void ctl.did(data.settingsEdit("max_leaves", n.ref)).then(after) }] : []),
    ...(n.kind === "job_failed" && n.ref ? [
      { ...bind("need.R.job_failed"), run: () => void ctl.did(data.retryJob(n.ref!)).then(after) },
      { ...bind("need.d.job_failed"), run: () => void ctl.did(data.dismissJob(n.ref!)).then(after) },
    ] : []),
    ...((n.kind === "question" || n.kind === "mention") && tid ? [{ ...bind("need.r.question"), run: () => ctl.reply(tid) }] : []),
    ...(n.kind === "stalled" && tid ? [
      { ...bind("need.n.stalled"), run: () => void ctl.did(data.post(tid, NUDGE)).then(after) },
      { ...bind("need.o.stalled"), run: () => ctl.ask(`hand #${tid} to — a coworker's name`, (s) => { if (s.trim()) void ctl.did(data.handOff(tid, s.trim())).then(after) }) },
      { ...bind("need.x.stalled"), run: () => ctl.ask(`close #${tid} — why it is dropped`, (s) => { if (s.trim()) void ctl.did(data.closeThread(tid, s.trim())).then(after) }) },
      { ...bind("need.r.stalled"), run: () => ctl.reply(tid) },
    ] : []),
    ...(n.kind === "verify_failed" && tid ? [{ ...bind("need.V.verify_failed"), run: () => void ctl.did(data.reverify(tid)).then(after) }] : []),
    ...(n.kind === "publish_failed" && tid ? [{ ...bind("need.R.publish_failed"), run: () => void ctl.did(data.republish(tid)).then(after) }] : []),
    ...(n.kind === "release_failed" && n.ref ? [{ ...bind("need.R.release_failed"), run: () => void ctl.did(data.retryRelease(n.ref!)).then(after) }] : []),
    ...(n.kind === "pr_blocked" && tid ? [
      { ...bind("need.b.pr_blocked"), run: () => void ctl.did(data.rebaseLanding(tid)).then(after) },
      { ...bind("need.L.pr_blocked"), run: () => void ctl.did(data.relandLanding(tid)).then(after) },
      { ...bind("need.v.pr_blocked", `show me: the thread${n.url ? ` (${n.url})` : ""}`), run: () => ctl.openReader(tid) },
    ] : []),
    ...(n.kind === "rollout" && n.ref ? [{ ...bind("need.d.rollout"), run: () => void ctl.did(data.dismissRollout(n.ref!)).then(after) }] : []),
    ...(n.kind === "stranded" ? [{ ...bind("need.X.stranded"), run: () => void ctl.did(data.retireStranded(n.key)).then(after) }] : []),
    ...(n.kind === "issue" && n.ref ? [{ ...bind("need.g.issue"), run: () => void ctl.did(data.fixIssue(n.ref!)).then(after) }] : []),
    ...(n.kind === "issue" && n.ref ? [{ ...bind("need.x.issue"), run: () => ctl.ask("resolve — why (naming the PR banks the sheriff's postmortem)", (s) => { if (s.trim()) void ctl.did(data.resolveIssue(n.ref!, s.trim())).then(after) }) }] : []),
    ...(n.kind === "publish_failed" && tid ? [{ ...bind("need.d.publish_failed"), run: () => ctl.ask("its PR's url — waited on until GitHub merges it", (s) => { if (s.trim()) void ctl.did(data.publishedByHand(tid, s.trim())).then(after) }) }] : []),
    ...(n.kind === "no_seat" && n.archetype && n.workspace_id != null ? [{ ...bind("need.h.no_seat", `hire a ${n.archetype}`), run: () => ctl.ask(`hire a ${n.archetype} — their name`, (s) => { if (s.trim()) void ctl.did(data.hire(n.workspace_id!, s.trim(), n.archetype!)).then(after) }) }] : []),
    ...(n.kind === "no_seat" && tid ? [{ ...bind("need.o.no_seat"), run: () => ctl.ask(`hand #${tid} to — a coworker's name`, (s) => { if (s.trim()) void ctl.did(data.handOff(tid, s.trim())).then(after) }) }] : []),
    ...(n.kind === "tool_denied" && tid && n.rule && !n.hook ? [{ ...bind("need.A.tool_denied", `allowed it: ${n.rule} is in your own settings (wakes the lead)`), run: () => void ctl.did(data.allowed(tid, n.rule!)).then(after) }] : []),
    ...(n.kind === "tool_denied" && tid ? [
      { ...bind("need.r.tool_denied"), run: () => ctl.reply(tid) },
      { ...bind("need.B.tool_denied"), run: () => ctl.ask(`#${tid} back to build — what to change`, (s) => { if (s.trim()) void ctl.did(data.sendBack(tid, "build", s.trim())).then(after) }) },
      { ...bind("need.u.tool_denied"), run: () => void ctl.did(data.refusalToUqbar(tid, n.text)).then(after) },
    ] : []),
    ...(n.kind === "quota" && n.workspace_id != null ? (n.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: o.label, run: () => void ctl.did(data.shiftSwitch(n.workspace_id!, o.key)).then(after) })) : []),
    ...(n.kind === "quota" ? [
      { ...bind("need.P.quota"), run: () => void ctl.did(data.pause("pencils_down")).then(after) },
      { ...bind("need.d.quota"), run: () => void ctl.did(data.dismissNeed(n.key)).then(after) },
    ] : []),
    ...(n.level === "decide" || n.kind === "ask" || n.kind === "stalled" ? [{ ...bind("need.d.decide"), run: () => void ctl.did(data.dismissNeed(n.key)).then(after) }] : []),
    ...(tid ? [...(n.kind === "pr_blocked" ? [] : [{ ...bind("need.v"), run: () => ctl.openReader(tid) }]), { ...bind("need.t"), run: () => void ctl.zoomInto(tid) }] : []),
  ]
  return acts.filter((a, i, all) => all.findIndex((b) => b.key === a.key) === i)
}

/** a need's one-line name: what kind, and where */
export const NEED_KIND: Record<data.Need["kind"], string> = { gate: "gate", question: "question", ask: "asks you", verify_failed: "verify red", stalled: "stalled", mention: "mentioned you", rollout: "rollout", seats: "waits for a seat", job_failed: "job failed", health: "the box", stranded: "stranded work", issue: "issue", blocked: "blocked on a ticket", publish_failed: "not on GitHub", release_failed: "cut failed", pr_blocked: "PR not merging", quota: "out of quota", no_seat: "no seat", tool_denied: "tool refused" }

export const NEED_TONE: Record<data.Need["kind"], string> = { gate: ROLE.attention, question: ROLE.key, ask: ROLE.key, verify_failed: ROLE.alarm, stalled: ROLE.attention, mention: ROLE.body, rollout: ROLE.live, seats: ROLE.attention, job_failed: ROLE.alarm, health: ROLE.alarm, stranded: ROLE.attention, issue: ROLE.alarm, blocked: ROLE.attention, publish_failed: ROLE.alarm, release_failed: ROLE.alarm, pr_blocked: ROLE.alarm, quota: ROLE.attention, no_seat: ROLE.attention, tool_denied: ROLE.alarm }

export function triageCard(app: State, ctl: Ctl): Card {
  if (!app.stuck) return { title: "TRIAGE", rows: [{ segs: [waiting(app, "looking…")] }], actions: [ctl.back1] }
  const rows: Row[] = []
  const section = (name: string, c: data.Capped<data.Stuck>, kind: StuckKind) => {
    if (!c.shown.length) return
    rows.push({ segs: [key(name)] })
    for (const s of c.shown) {
      const segs = kind === "blocker"
        ? [key(`  #${s.issue_id} `), ...(s.ticket_id ? [live(`→ ticket #${s.ticket_id} ${s.ticket_status ?? ""} `)] : []), dim(`${s.created_at ? ago(s.created_at) : ""} ${s.found_by ?? ""}  `), pink(oneLine(s.summary ?? s.text))]
        : [key(`  #${s.thread_id} `), plain(s.title), pink(`  ${s.text}`)]
      rows.push({ segs, open: kind === "blocker" ? () => ctl.open({ kind: "issue", id: s.issue_id! }) : () => ctl.openReader(s.thread_id), ref: { s, kind } })
    }
    if (c.more) rows.push({ segs: [dim(`  +${c.more} more`)] })
  }
  section("BLOCKERS — open issues", app.stuck.blockers, "blocker"); section("FAILED CHECKS", app.stuck.failed_checks, "check")
  if (app.stuck.failed_checks.shown.length) rows.push({ segs: [dim("  y re-runs verify, only for a thread at its verify stage")] })
  section("NOBODY LEADS", app.stuck.unled, "unled")
  // the cursor lands on the first row only after this build, so its actions are read from where it will be
  const at = rows[rows[app.sel]?.open ? app.sel : rows.findIndex((r) => r.open)]?.ref as { s: data.Stuck; kind: StuckKind } | undefined
  return {
    title: `TRIAGE · ${app.stuck.count} known problems · the sheriff's`, rows: rows.length ? rows : [{ segs: [dim("nothing is stuck. the beacon is dark.")] }],
    actions: [...(at ? stuckActions(app, ctl, at.s, at.kind) : []), ctl.back1],
  }
}

export function issueCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "issue" }>): Card {
  const id = mode.id, s = app.stuck?.blockers.shown.find((x) => x.issue_id === id)
  if (!app.stuck) return { title: `ISSUE #${id}`, rows: [{ segs: [waiting(app, "looking…")] }], actions: [ctl.back1] }
  if (!s) return { title: `ISSUE #${id}`, rows: [{ segs: [dim("it is no longer an open blocker: fixed, resolved or owned.")] }], actions: [ctl.back1] }
  const w = Math.max(20, paneW() - 4), paras = (t: string) => t.split("\n").flatMap((p) => (p.trim() ? wrap(p, w) : [""])).map((l): Row => ({ segs: [plain(l)] }))
  const rows: Row[] = [
    { segs: [dim(`found by ${s.found_by ?? "?"} · ${s.created_at ? ago(s.created_at) : "?"} ago · raised on `), key(`#${s.thread_id} `), plain(s.title)] },
    ...(s.ticket_id ? [{ segs: [live(`being fixed: ticket #${s.ticket_id} (${s.ticket_status ?? "?"}); it comes back to you to close when that ticket is done`)] }] : []),
    { segs: [plain("")] }, { segs: [key("SUMMARY")] }, ...paras(s.summary ?? s.text),
    ...(s.evidence ? [{ segs: [plain("")] }, { segs: [key("EVIDENCE")] }, ...paras(s.evidence)] : []),
  ]
  return { title: `ISSUE #${id}`, tint: ROLE.attention, rows, actions: [...stuckActions(app, ctl, s, "blocker"), ctl.back1] }
}

export function needsCard(app: State, ctl: Ctl): Card {
  // what waits by who acts: the phone (an answer owed), the machine (information), the clipboard (the crew's); then what's under way
  // a settled row says how Uqbar handled it; a passed-up one carries Uqbar's recommendation
  const detail = (n: data.Need): Row["segs"] =>
    n.route === "settled" ? [{ s: `settled by Uqbar · ${n.why ?? ""}`, fg: ROLE.body }]
      : n.route === "uqbar" ? [dim(`with Uqbar · ${n.text.replace(/\s+/g, " ")}`)]
      : [{ s: n.text.replace(/\s+/g, " "), fg: n.surface === "phone" ? ROLE.prose : ROLE.inactive }, ...(n.recommendation ? [{ s: `  tip: ${n.recommendation}`, fg: ROLE.key }] : [])]
  const row = (n: data.Need): Row => ({
    segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(n.thread_id ? [tidSeg(n.thread_id)] : []),
      ...(n.surface === "clipboard" ? [{ s: `${clipLabel(n)}  `, fg: ROLE.key }] : []),
      { s: n.title, fg: ROLE.prose }, dim(`  ${ago(n.at)}  `), ...detail(n)],
    open: n.thread_id ? () => ctl.openReader(n.thread_id!) : undefined, ref: n,
  })
  const TONE = { phone: ROLE.attention, machine: ROLE.body, settled: ROLE.body, clipboard: ROLE.inactive, uqbar: ROLE.inactive }
  const live = app.all.threads.filter((t) => t.live && !t.standing && !app.needs.some((n) => n.thread_id === t.id))
  const section = (label: string, bg: string, note: string): Row => ({ segs: [{ s: ` ${label} `, fg: ROLE.ground, bg, bold: true }, dim(`  ${note}`)] })
  const rows: Row[] = [
    ...inboxSections(app.bySurface).flatMap((s) => [section(s.label, TONE[s.surface], s.note), ...s.items.map(row)]),
    ...(live.length ? [section(`UNDER WAY · ${live.length}`, ROLE.live, "being worked on"), ...live.map((t): Row => ({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, dim(`  ${t.lead ?? ""}${t.stage ? ` · ${t.stage}` : ""}`)], open: () => ctl.goThread(t.id, t.workspace_id) }))] : []),
  ]
  const n = rows[app.sel]?.ref as data.Need | undefined
  const acts: Action[] = !n ? [] : [...needActions(app, ctl, n), { ...bind("needs.f"), run: () => ctl.open({ kind: "decide", i: Math.max(0, app.needs.indexOf(n)) }) }]
  return {
    title: app.needs.length ? `WAITING ON YOU · ${app.bySurface.counts.phone} on the phone · ${app.bySurface.counts.machine} on the machine · ${app.bySurface.counts.clipboard} on the clipboard` : "WAITING ON YOU",
    tint: app.bySurface.counts.phone ? ROLE.attention : app.needs.length ? ROLE.body : ROLE.live,
    rows: rows.length ? rows : [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }],
    actions: [...acts.filter((a, i, all) => all.findIndex((b) => b.key === a.key) === i), ctl.back1],
  }
}

export function decideCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "decide" }>): Card {
  // one waiting item at a time, everything to decide it on the card; acting moves to the next
  const order = app.needs // phone first, then the machine, then the clipboard
  if (!order.length) return { title: "WAITING ON YOU", tint: ROLE.live, rows: [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }], actions: [ctl.back1] }
  const i = Math.min(mode.i, order.length - 1), n = order[i]!, tid = n.thread_id ?? null
  const t = tid ? app.all.threads.find((x) => x.id === tid) : undefined
  const step = (d: number) => ctl.open({ kind: "decide", i: (i + d + order.length) % order.length })
  const rows: Row[] = [
    { segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(tid ? [tidSeg(tid)] : []), { s: n.title, fg: ROLE.prose, bold: true }], open: tid ? () => ctl.openReader(tid) : undefined },
    { segs: [dim(`${n.surface === "clipboard" ? `the crew's: ${clipLabel(n)}` : n.surface === "machine" ? "for your information" : "an answer is owed"} · ${ago(n.at)}${t ? ` · ${t.lead ?? "no lead"}${t.stage ? ` at ${t.stage}` : ""}` : ""}`)] },
    { segs: [plain("")] },
    ...wrap(n.text, paneW() - 4).map((l): Row => ({ segs: [plain(l)] })),
  ]
  return {
    title: `DECIDE · ${i + 1} of ${order.length}`,
    tint: n.surface === "clipboard" ? ROLE.inactive : n.surface === "machine" ? ROLE.body : ROLE.attention,
    rows,
    actions: [...needActions(app, ctl, n), { ...bind("decide.n"), run: () => step(1) }, { ...bind("decide.p"), run: () => step(-1) }, { ...bind("decide.l"), run: () => ctl.open({ kind: "needs" }) }, ctl.back1],
  }
}
