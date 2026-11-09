import { cardState, statusGlyph, statusTone, type CardState } from "../../kit/crew"
import { ROLE } from "../../kit/palette"
import { shirtOf } from "../../kit/sprites"
import { type Thread } from "../../kit/types"
import { handToUqbar } from "../talk"
import { studyOf } from "../../kit/uqbar"
import * as data from "../data"
import { bind } from "../keys"
import { wrap } from "../editor"
import { timelineRows } from "../timeline"
import { type Seg } from "../term"
import { type Mode, type Row, type Action, type Card } from "../state"
import { authorColor, boardCtx, paneRows, threadOf, view } from "../select"
import { dim, key, paneW, pink, plain, stateSeg } from "../ui"
import { answerWithNote } from "./needs"
import type { State } from "../state"
import type { Ctl } from "../ctl"

/** the verbs on a thread, wherever it is open (its card, a person's, the reader) */
export function threadActions(app: State, ctl: Ctl, tid: number, inReader = false): Action[] {
  const th = threadOf(app, tid)
  const prompt = th?.prompt
  const answers = (prompt?.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void ctl.did(data.answer(prompt!.id, o.key)) }))
  return [
    ...answers,
    ...(prompt?.options?.length ? [{ ...bind("thread.n"), run: () => answerWithNote(app, ctl, prompt.id, prompt.options!) }] : []),
    ...(inReader ? [] : [{ ...bind("thread.v"), run: () => ctl.openReader(tid) }]),
    { ...bind("thread.r"), run: () => ctl.reply(tid) },
    ...(studyOf(app.all.threads, app.ws) !== null && studyOf(app.all.threads, app.ws) !== tid ? [{ ...bind("thread.u"), run: () => void ctl.did(handToUqbar(app.all.threads, app.ws, tid)) }] : []),
    // the heavy hitter: an @aleph from you calls it in on this thread (Server.Aleph); it answers and leaves
    { ...bind("thread.a"), run: () => ctl.ask("call in the Aleph — what should it look at?", (q) => { if (q.trim()) void ctl.did(data.post(tid, `@aleph ${q.trim()}`)) }) },
    ...(th?.awaiting && th.stage ? [{ ...bind("thread.A", `approve: ${th.awaiting}`), run: () => void ctl.did(data.approve(tid)) }] : []),
    ...(th?.stage ? [{ ...bind("thread.>"), run: () => void ctl.did(data.advance(tid)) }] : []),
    ...(th && cardState(view(app), th, boardCtx(app))?.atCap ? [{ ...bind("thread.S"), run: () => { if (app.reader) ctl.closeReader(); ctl.open({ kind: "settings" }) } }] : []),
    { ...bind("thread.t"), run: () => void ctl.zoomInto(tid) },
    { ...bind("thread.g"), run: () => void ctl.zoomGit(tid) },
    ...(th?.stage ? [{ ...bind("thread.d"), run: () => void ctl.pickDoc(tid) }, { ...bind("thread.R"), run: () => { if (app.reader) ctl.closeReader(); ctl.open({ kind: "review", tid }) } }] : []),
    {
      ...bind("thread.h"), run: () => {
        const bench = view(app).bench
        ctl.find(`HAND #${tid} OFF TO`, bench.map((c) => ({ segs: [{ s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}${c.name === th?.lead ? " · leads it now" : ""}`, fg: ROLE.inactive }], text: c.name, run: () => { app.picker = null; void ctl.did(data.handOff(tid, c.name)) } })))
      },
    },
    {
      ...bind("thread.P"), run: () => {
        ctl.find(`MOVE #${tid} TO PROJECT`, view(app).projects.map((p) => ({ segs: [{ s: p.name, fg: ROLE.prose }], text: p.name, run: () => { app.picker = null; void ctl.did(data.move(tid, p.id)) } })))
      },
    },
    ...(th ? [th.paused_at ? { ...bind("thread.P.paused"), run: () => void ctl.did(data.pauseThread(tid, "resume")) } : { ...bind("thread.P.running"), run: () => void ctl.did(data.pauseThread(tid, "pause")) }] : []),
    { ...bind("thread.x"), run: () => ctl.ask2(`close #${tid} as done`, () => ctl.did(data.closeThread(tid))) },
    { ...bind("thread.D"), run: () => ctl.ask2(`delete #${tid} for good (its worktree goes too, if it loses nothing)`, () => { if (app.reader) ctl.closeReader(); ctl.back(); void ctl.did(data.deleteThread(tid)) }) },
  ]
}

/** the actions a running thread's card adds: step into the session, flip activity and conversation */
export function liveActions(app: State, ctl: Ctl, tid: number): Action[] {
  if (!threadOf(app, tid)?.live) return []
  return [
    { ...bind("live.enter"), run: () => void ctl.zoomInto(tid) },
    { ...bind("live.c", app.talkView.has(tid) ? "their activity" : "the conversation"), run: () => { if (!app.talkView.delete(tid)) app.talkView.add(tid); ctl.draw() } },
  ]
}

export const STAGE_RING = ["intent", "spec", "plan", "build", "verify", "review", "landed"]

/** a thread's rows for a card; `above`: the card's own rows over them, so the tail still ends in view */
export function threadRows(app: State, ctl: Ctl, th: Thread | undefined, tid: number, above = 0): Row[] {
  const v = app.threads.get(tid), out: Row[] = []
  out.push({ segs: [key(`#${tid} `), plain(th?.title ?? "")] })
  // a workline's stages as a track (done ones lit, the current one a chip); a plain thread's lead and state
  const cur = th?.stage ? STAGE_RING.indexOf(th.stage) : -1
  out.push({
    segs: [
      ...(th?.stage
        ? STAGE_RING.flatMap((st, i): Seg[] => [...(i ? [dim(" ▸ ")] : []), i === cur ? { s: ` ${st === "landed" && th.landing ? "landing" : st} `, fg: ROLE.ground, bg: th.awaiting ? ROLE.attention : ROLE.key, bold: true } : { s: st, fg: i < cur ? ROLE.live : ROLE.inactive }])
        : [dim("thread")]),
      ...(th?.lead ? [dim("  · "), { s: th.lead, fg: authorColor(app, th.lead), bold: true }] : []),
      ...(th?.live ? [{ s: `  ${statusGlyph("working")} running`, fg: statusTone("working") }] : []),
    ],
  })
  // a board card's state, and the one thing that moves it
  const st = th && !th.duty && (th.stage || (th.lead && !th.standing)) ? cardState(view(app), th, boardCtx(app)) : null
  if (th && st) { const n = nextStep(th, st); out.push({ segs: [stateSeg(st), { s: st.why, fg: st.kind === "needs" ? ROLE.attention : ROLE.prose }, dim("  → "), key(`${n.key} `), plain(n.label)] }) }
  if (th?.prompt) {
    out.push({ segs: [pink("asks: "), plain(th.prompt.summary)] })
    const pid = th.prompt.id
    th.prompt.options?.forEach((o, i) => out.push({ segs: [key(` ${i + 1} `), plain(o.label)], open: () => ctl.did(data.answer(pid, o.key)) }))
  } else if (th?.awaiting && !st) out.push({ segs: [pink(`awaits ${th.awaiting}${th.stage ? " — A approves" : ""}`)] })
  // a running thread's activity, every event the server keeps: the pane opens on the newest and
  // scrolls back (pgup/pgdn, the wheel) — unless you flipped to the conversation
  if (th?.live && !app.talkView.has(tid)) {
    const feed = v?.activity ?? [], live = new Set(app.all.roster.filter((r) => r.thread_id === tid && r.thinking).map((r) => r.agent))
    out.push({ segs: [{ s: " LIVE ", fg: ROLE.ground, bg: ROLE.live, bold: true }, dim("  what they're doing · ⏎ step in · c the conversation")] })
    if (!feed.length) out.push({ segs: [dim("  nothing reported yet — ⏎ steps into their screen")] })
    out.push(...timelineRows(feed, { width: paneW() - 2, colorOf: (author) => authorColor(app, author), live }))
    return out
  }
  // the conversation's tail, wrapped, as much as fits; `v` reads the whole of it
  const room = paneRows(app) - above - out.length, tail: Row[] = []
  for (const m of [...(v?.messages ?? [])].reverse()) {
    const lines = wrap(`${m.author}: ${m.body}`, paneW() - 4)
    const tone = m.author === "tlon" ? ROLE.inactive : ROLE.prose
    const rowsOf = lines.map((l, i): Row => ({ segs: i ? [{ s: `  ${l}`, fg: tone }] : [{ s: `${m.author}: `, fg: authorColor(app, m.author), bold: true }, { s: l.slice(m.author.length + 2), fg: tone }] }))
    tail.unshift(...rowsOf)
    if (tail.length >= room) break
  }
  out.push(...tail.slice(-room))
  if (!v?.messages.length && v?.peek) for (const l of v.peek.split("\n").filter((x) => x.trim()).slice(-4)) out.push({ segs: [dim(l)] })
  return out
}

/** the one thing to do about a board card, by where it stands */
export function nextStep(th: Thread, st: CardState): { key: string; label: string } {
  const options = th.prompt?.options?.length ?? 0
  if (st.kind === "needs" && options) return { key: options > 1 ? `1–${Math.min(9, options)}` : "1", label: "answer it" }
  if (st.kind === "needs" && th.awaiting && th.stage) return bind("thread.A", `approve: ${th.awaiting}`)
  if (st.atCap) return bind("thread.S", "raise the cap in settings")
  return bind("thread.v", "open the reader")
}

export function threadCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "thread" }>): Card {
  const tid = mode.tid
  const th = threadOf(app, tid)
  return { title: `THREAD #${tid}${th?.stage ? ` · workline ${th.stage}` : ""}${th?.paused_at ? " · ⏸ paused" : ""}`, rows: threadRows(app, ctl, th, tid), tint: th?.awaiting || th?.prompt ? ROLE.attention : th?.lead ? authorColor(app, th.lead) : ROLE.key, actions: [...liveActions(app, ctl, tid), ...threadActions(app, ctl, tid), ctl.back1] }
}
