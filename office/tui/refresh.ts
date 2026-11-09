import { arrivals } from "../kit/door"
import { clockFace } from "../kit/eggs"
import { bump as bumpTally, findSecret, newlyWon, night, serialize as serializeTally, won as wonTrophies, type Tally } from "../kit/trophies"
import { reactLine, seatLine } from "../kit/seat-voices"
import type { EventKind } from "../kit/events"
import { resolve as resolveWhim } from "../kit/whimsy"
import { tickFromTriage } from "../kit/scharlach"
import { lastLanding } from "../kit/tv"
import { operatorOf, type Agents } from "../kit/types"
import { WideRoom } from "../rooms/wide"
import { lobbyOf, replies } from "./talk"
import * as data from "./data"
import { ESC, out } from "./term"
import { earmarkOf, earmarksOut, freshPosts, handoffFrom } from "../kit/plane"
import { TRAY, SAID, EARS, LOOKED, writeState, TROPHY_FILE } from "./state"
import { changed, view } from "./select"
import { cardKey } from "./ui"
import { NEED_KIND } from "./cards/needs"
import type { Screen } from "./ctl"
import { draw } from "./draw"
import { syncDump } from "./zoom"
import type { State } from "./state"

/** a seat's line for a scripted event, kept out of what it said lately */
export const reactFor = (app: State, who: string, kind: EventKind): string => {
  const recent = app.recentBanter.get(who) ?? []
  const line = reactLine(who, kind, recent)
  app.recentBanter.set(who, [line, ...recent].slice(0, 8))
  return line
}

export function heard(app: State, turns: { who: string; line: string }[]) {
  // a restart re-reads the server's recent lines: the log already has them
  const fresh = turns.filter((t) => !app.said.some((x) => x.who === t.who && x.line === t.line))
  app.said = [...app.said, ...fresh.map((t) => ({ at: Date.now(), ...t }))].slice(-50)
  writeState(SAID, JSON.stringify(app.said))
  if (fresh.length) record(app, bumpTally(app.trophies, "balloons", fresh.length))
}

export const stampLooked = (app: State) => { app.looks.lookedAt = Math.floor(Date.now() / 1000); writeState(LOOKED, String(app.looks.lookedAt)) }

export async function refreshOnce(app: State, ctl: Screen) {
  for (const w of app.dumpSent.keys()) syncDump(app, ctl, w, true)
  // the snapshot lands, and shows, as soon as it comes: the inbox read beside it takes seconds (a git
  // check per stray worktree), and a finder opened meanwhile would list nothing
  const rest = Promise.all([data.needs(), data.settings()])
  app.all = await data.status()
  if (app.officeRev === undefined && app.all.ok) app.officeRev = app.all.revs?.office ?? null
  ctl.settleWorkspace()
  draw(app, ctl)
  let knobs: data.Settings | null
  ;[app.bySurface, knobs] = await rest
  app.needs = app.bySurface.items
  app.settings = knobs ?? app.settings
  if (app.all.ok && app.lastOk.ok) tellNews(app, ctl, app.lastOk, app.lastOkNeeds)
  if (app.all.ok) { app.lastOk = app.all; app.lastOkNeeds = app.needs; tickerOn(app, app.all) }
  const tid = ctl.openThread()
  await Promise.all([tid !== null ? loadThread(app, tid) : null, app.reader ? app.reader.reload() : null, loadCard(app), loadFeed(app, ctl), loadMargin(app)])
  await chatter(app, ctl)
  void tickLedger(app)
  draw(app, ctl)
}

/**
 * Scharlach's demerit ledger ticks when a coworker's build goes red. The sheriff's workspace's triage
 * carries each failed check's thread (whoever led it); a red first seen ticks, the same red held does
 * not, and one that clears then re-reds ticks again. Presentation only — it never touches the work.
 */
export async function tickLedger(app: State) {
  if (!app.all.ok) return
  const sws = app.all.bench.find((c) => c.archetype === "sheriff")?.workspace_id
  if (sws == null) return
  const count = app.all.triage[String(sws)] ?? 0
  record(app, night(app.trophies, app.world ? app.world.now() : new Date(), count > 0))
  const t = count > 0 ? await data.triage(sws) : null
  if (count > 0 && !t) return
  const before = new Map(app.ledger.demerits)
  app.ledger = tickFromTriage(app.ledger, count, t?.failed_thread_ids ?? t?.failed_checks.shown.map((s) => s.thread_id) ?? [], app.all.threads)
  // rimworld: a red build sours that coworker's afternoon — room-local, the room's own reading of what it already saw
  for (const [who, n] of app.ledger.demerits) if (n > (before.get(who) ?? 0)) for (const r of app.rooms.values()) r.sourMood(who)
}

/** what changed since the last look that you'd want to hear about even with the office in the back */
export function tellNews(app: State, ctl: Screen, before: Agents, beforeNeeds: data.Need[]) {
  // only an answer owed rings: a new item on the phone; several at once are one notification
  const was = new Set(beforeNeeds.map((n) => n.key))
  const fresh = app.bySurface.phone.filter((n) => !was.has(n.key))
  if (fresh.length) out("\x07") // something new waits on you: the terminal's bell
  if (fresh.length === 1) notify(needTitle(fresh[0]!), fresh[0]!.text)
  else if (fresh.length > 1) notify(`${fresh.length} things wait on you`, fresh.map(needTitle).join(" · "))
  if (before.health?.state === "ok" && app.all.health?.state === "warn") notify("tlon needs a look", app.all.health.problems.join("; "))
  for (const kind of arrivals(before, app.all, beforeNeeds, app.needs)) ctl.room().ring(kind)
  releaseOnTv(app, before, app.all)
}

/** the TV's ticker channel crawls the release, the merge queue, the phone and the newest landing's subject */
export function tickerOn(app: State, a: Agents) {
  const t = { sha: a.release?.sha ?? null, queue: a.health?.merge_queue?.length ?? 0, phone: app.bySurface.counts.phone, last: lastLanding(a) }
  for (const r of app.rooms.values()) if (r instanceof WideRoom) r.setTicker(t)
}

/** a cut puts Uqbar's entry on the TV; the next snapshot that holds the same sha ends it */
export function releaseOnTv(app: State, before: Agents, after: Agents) {
  if (!before.ok || !after.ok || !after.release) return
  for (const r of app.rooms.values()) {
    if (!(r instanceof WideRoom)) continue
    if (before.release?.sha !== after.release.sha) r.cut(after.release.sha, after.release.notes ?? [])
    else if (r.cutting) r.cutDone()
  }
}

/** a desktop notification (OSC 777, as ghostty, kitty, WezTerm and foot take it) */
export function notify(title: string, body: string) {
  const clean = (s: string) => s.replace(/[;\x07\x1b]/g, " ").slice(0, 200)
  out(`${ESC}]777;notify;${clean(title)};${clean(body)}${ESC}\\`)
}

export async function loadMargin(app: State) { app.notes = app.ws === null ? [] : await data.margin(app.ws) }

export function record(app: State, next: Tally) {
  if (next === app.trophies) return
  for (const tr of newlyWon(app.trophies, next)) app.status = `trophy won: ${tr.name}`
  app.trophies = next
  writeState(TROPHY_FILE, serializeTally(next))
  for (const r of app.rooms.values()) if (r instanceof WideRoom) r.setTrophies(wonTrophies(next).length)
}

/** the tallies only the sim knows: a drill begun, treats given, a secret clock face */
export function watchTrophies(app: State) {
  let next = app.trophies
  const alarmed = [...app.rooms.values()].some((r) => r.alarmed)
  if (alarmed && !app.wasAlarmed) next = bumpTally(next, "drills")
  app.wasAlarmed = alarmed
  for (const r of app.rooms.values()) {
    const n = r.treats - (app.seenTreats.get(r) ?? 0)
    app.seenTreats.set(r, r.treats)
    if (n > 0) next = bumpTally(next, "treats", n)
  }
  if (["404", "π"].includes(clockFace(app.world ? app.world.now() : new Date()))) next = findSecret(next, "clock")
  record(app, next)
}

export async function loadFeed(app: State, ctl: Screen) {
  if (app.ws === null) return
  const first = !app.feed.length
  app.feed = (await data.activity(app.ws)) ?? app.feed
  const v = view(app), r = ctl.room()
  for (const x of freshPosts(app.feed, app.flown, first)) {
    if (r instanceof WideRoom && r.fly(x.thread_id!, v, handoffFrom(app.feed, x.thread_id!, Date.now()))) {
      app.earmarked.add(earmarkOf(x.thread_id!, x.at, x.who))
      record(app, bumpTally(app.trophies, "planes"))
      writeState(EARS, earmarksOut(app.earmarked))
    }
  }
  // a first run starts with the tray read, not with everything that ever happened in it
  if (!app.trayRead && app.feed[0]) { app.trayRead = app.feed[0].at; writeState(TRAY, app.trayRead) }
}

export async function chatter(app: State, ctl: Screen) {
  if (app.ws === null) return
  const here = app.ws
  const dials = resolveWhim(app.whim), banter = dials.banter
  // the server writes these lines lazily, spending model tokens only when asked: with banter off, don't ask
  if (banter) ctl.room().hear(await data.pets(app.ws, ctl.room().petProfile()))
  // generated visitors, puns and reactions reach the room only past `curated`; the room ignores a pool it is not given
  ctl.room().setToys(dials.weirdness === "curated" ? null : await data.toys(here))
  // two together in the room: with souls on the server writes what they say now (from their souls), said turn by turn;
  // with them off, in --sandbox, or wherever the server wrote nothing, each says a canned line in their own voice
  ctl.room().onTogether = (situation, a, b) => !banter ? undefined : void (dials.souls ? data.talk(here, situation, a, b) : Promise.resolve([])).then((turns) => {
    const said = turns.length ? turns : [a, b].map((who) => {
      const recent = app.recentBanter.get(who) ?? []
      const line = seatLine(who, recent, situation)
      app.recentBanter.set(who, [line, ...recent].slice(0, 8))
      return { who, line }
    })
    ctl.room().converse(said); heard(app, said); changed(app)
  })
  app.cork = banter ? await data.corkboard(app.ws) : []
  ctl.room().pinboard(app.cork)
  app.ideas = await data.suggestions(app.ws)
  ctl.room().suggestionBox(app.ideas)
  // a conversation the server wrote arrives as lines sharing one `at`: said as one, turn by turn
  const convos = new Map<number, { who: string; line: string }[]>()
  for (const b of banter ? await data.banter(app.ws) : []) {
    const k = `${b.at} ${b.agent} ${b.line}`
    if (app.seenLines.has(k)) continue
    app.seenLines.add(k)
    convos.set(b.at, [...(convos.get(b.at) ?? []), { who: b.agent, line: b.line }])
  }
  if (banter) for (const turns of convos.values()) { ctl.room().converse(turns); heard(app, turns); changed(app) }
  await answers(app, ctl, app.ws)
}

export async function answers(app: State, ctl: Screen, w: number) {
  const lobby = lobbyOf(view(app).threads, w)
  const v = lobby === null ? null : await data.thread(lobby)
  if (!v) return
  const fresh = replies(v.messages, operatorOf(app.all)).filter((r) => !app.answered?.has(r.id))
  const first = app.answered === null
  app.answered ??= new Set()
  for (const r of fresh) {
    app.answered.add(r.id)
    if (first) continue
    ctl.room().say(r.agent, r.line)
    if (app.mode.kind !== "home") notify(`${r.agent} answered`, r.line)
    changed(app)
  }
}

export async function loadThread(app: State, tid: number) { const v = await data.thread(tid); if (v) app.threads.set(tid, v) }

/** the open card's own read, if it has one */
export async function loadCard(app: State) {
  if (app.ws === null) return
  const w = app.ws
  const key = cardKey(app.mode)
  const why = await data.reading(() => readCard(app, w))
  if (why) app.readWhys.set(key, why); else app.readWhys.delete(key)
}

export async function readCard(app: State, w: number) {
  switch (app.mode.kind) {
    case "archive": app.archived = await data.archive(w); break
    case "triage": case "issue": app.stuck = await data.triage(w); break
    case "health": [app.rack, app.settings] = await Promise.all([data.health(), data.settings()]); break
    case "memory": app.shelf = await data.memory(w); break
    case "ticket": case "epic": case "column": app.tickets = (await data.board(w)) ?? app.tickets; break
    case "card": app.card = await data.workspaceCard(w); break
    case "settings": app.settings = await data.settings(); break
    case "review": app.review = await data.review(app.mode.tid); break
    case "calendar": app.cal = await data.schedules(w); break
    case "life": app.lifeCard = (await data.life(w)) ?? app.lifeCard; break
    case "build": app.lifeCard = await data.life(w); break
    case "pages": app.dumpPages = await data.dumpPages(w); break
    case "runs": case "run": app.board = (await data.runs(app.mode.id)) ?? app.board; app.cal ??= await data.schedules(w); break
    case "tray": app.trayRead = app.feed[0]?.at ?? app.trayRead; writeState(TRAY, app.trayRead); changed(app); break
  }
}

export const needTitle = (n: data.Need) => `${NEED_KIND[n.kind]}${n.thread_id ? ` #${n.thread_id}` : ""} — ${n.title}`
