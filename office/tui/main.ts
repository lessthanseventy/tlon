// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { arrivals } from "../kit/door"
import { babelPage, clockFace, hasFound, isKonami, KONAMI } from "../kit/eggs"
import { bump as bumpTally, findSecret, newlyWon, night, serialize as serializeTally, won as wonTrophies, type Tally } from "../kit/trophies"
import { existsSync, mkdirSync, readFileSync, unlinkSync, watchFile, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { marginInk } from "../kit/margin"
import { reactLine, seatLine } from "../kit/seat-voices"
import type { EventKind } from "../kit/events"
import { save as saveWhim } from "../kit/whimsy-file"
import { resolve as resolveWhim, type State as WhimState } from "../kit/whimsy"
import { tickFromTriage, tickSlap } from "../kit/scharlach"
import { busiest, COLS, crewOf, needsYou, type Act } from "../kit/crew"
import { resolvePets } from "../kit/pets"
import { renderHome } from "../kit/homeart"
import { mailbox } from "../kit/mailbox"
import { phoneBar, ringFrame } from "../kit/surfaces"
import { lastLanding } from "../kit/tv"
import { baseLook, overrideFor, trimCustom } from "../kit/looks"
import { ROLE } from "../kit/palette"
import { bedScene, lifeHeader, streakFrames } from "../kit/life"
import { usageHeader } from "../kit/usage"
import { BLANK_SOUL, candidateOf } from "../kit/hall"
import { stepRow } from "./hall"
import { stepStoreRow } from "./store"
import { shirtOf } from "../kit/sprites"
import { flagOn, operatorOf, type Agents } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"
import { BAND, OFF_DOOR, OFF_W, WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import { say, lobbyOf, replies, conversation, speech } from "./talk"
import * as data from "./data"
import { adder, bind, hints, LEGEND_CHARS } from "./keys"
import { PLAY, roomKey } from "./sandbox"
import { Editor } from "./editor"
import { rank } from "./fuzzy"
import { ticketPicks } from "./finder"
import { loadFloor } from "./home"
import { loadPets } from "./pets"
import { geometry, hitAt, kittyImage, measureFor, textLayer } from "./paint"
import { Reader, type ReaderDeps } from "./reader"
import { footLines, follow as followSel, offset, type Hint, type Window } from "./pane"
import { badge, cells, ESC, leave, line, out, type Input, type Seg } from "./term"
import { rows as vtRows, TerminalView, type Target } from "./terminal"
import { centerViewport, clipFrame, panViewport, type Viewport } from "./viewport"
import { downHeader } from "./down"
import { oneInFlight } from "./flight"
import { earmarkOf, earmarksOut, freshPosts, handoffFrom } from "../kit/plane"
import { State, STATE_DIR, STATE, TRAY, SAID, EARS, LOOKED, TOY_KEYS, SOULS, OFFICE, writeState, TROPHY_FILE, type Mode, type Row, type Cycle, type Prompt, type Pick, type Action } from "./state"
import { detail } from "./cards/index"
import { boardCtx, cardBox, changed, checkingId, crewOn, crewsOf, hallCtx, nextCrew, threadOf, view, wsName } from "./select"
import { ACTIONS_W, DETAIL, cardKey, cols, dim, key, keyName, paneW, pink, plain, stamp, tidSeg } from "./ui"
import { NEED_KIND } from "./cards/needs"
import { newSchedule } from "./cards/schedule"
import { threadActions } from "./cards/thread"
import { GAMES } from "./cards/home"
import { boot, followPets, relaunch } from "./boot"
import type { Boot } from "./ctl"

const app = new State()

if (app.world) data.useFake(app.world)

/** step an ordering, keeping the cursor on the row (by its `ref`) it was on */
function resort(step: () => void) {
  const was = app.rows[app.sel]?.ref
  step()
  const at = was === undefined ? -1 : detail(app, ctl).rows.findIndex((r) => r.ref === was)
  if (at >= 0) app.sel = at
  draw()
}

/** a thread with an open prompt opens with its box unfocused, so 1–9 answer at once */
const asks = (tid: number) => !!threadOf(app, tid)?.prompt

/** a seat's line for a scripted event, kept out of what it said lately */
const reactFor = (who: string, kind: EventKind): string => {
  const recent = app.recentBanter.get(who) ?? []
  const line = reactLine(who, kind, recent)
  app.recentBanter.set(who, [line, ...recent].slice(0, 8))
  return line
}
function heard(turns: { who: string; line: string }[]) {
  // a restart re-reads the server's recent lines: the log already has them
  const fresh = turns.filter((t) => !app.said.some((x) => x.who === t.who && x.line === t.line))
  app.said = [...app.said, ...fresh.map((t) => ({ at: Date.now(), ...t }))].slice(-50)
  writeState(SAID, JSON.stringify(app.said))
  if (fresh.length) record(bumpTally(app.trophies, "balloons", fresh.length))
}
const stampLooked = () => { app.looks.lookedAt = Math.floor(Date.now() / 1000); writeState(LOOKED, String(app.looks.lookedAt)) }

/** a click on the header's crew: the next crew goes on */
const toggleShift = () => {
  const to = nextCrew(app)
  if (app.ws !== null && to) void did(data.shiftSwitch(app.ws, to))
}
/** the crew on, once the workspace has crews; nothing for one with none */
const shiftHeader = () => (crewsOf(app, app.ws).length ? `⇄ ${crewOn(app)} crew` : null)
/** the header's queues: what is checked and what is merged right now */
function queuesHeader(): string | null {
  const c = app.all.health?.checks, mq = app.all.health?.merge_queue ?? []
  const landing = mq.find((m) => m.state === "landing"), queued = mq.filter((m) => m.state === "queued").length
  const parts = [
    c?.running ? (checkingId(app) ? `✓ checking #${checkingId(app)}` : "✓ a full check runs") : null,
    c?.waiting.length ? `+${c.waiting.length} waiting` : null,
    landing ? `⤵ landing #${landing.thread_id}` : null,
    queued ? `${queued} queued to land` : null,
  ].filter(Boolean)
  return parts.length ? parts.join(" · ") : null
}
const room = () => { const k = app.ws ?? 0; let r = app.rooms.get(k); if (!r) { app.rooms.set(k, (r = app.wide ? new WideRoom(app.wide) : new RailRoom())); r.setWhimsy(resolveWhim(app.whim)); if (app.petsNow) r.setPets(app.petsNow); if (r instanceof WideRoom) { r.setHome(app.homeNow); r.setTrophies(wonTrophies(app.trophies).length) } r.reactLine = reactFor; r.onSlap = () => { app.ledger = tickSlap(app.ledger) } } return r }
/** the dial moved: remember it and hand every room the resolved dials */
function setWhim(s: WhimState) {
  app.whim = s
  saveWhim(OFFICE, s)
  for (const r of app.rooms.values()) r.setWhimsy(resolveWhim(s))
  changed(app)
}
const unread = () => app.feed.filter((x) => x.at > app.trayRead && x.who !== operatorOf(app.all)).length

function choose(id: number | null) {
  if (id !== app.ws) { app.feed = []; app.card = null }
  app.ws = id
  writeState(STATE, id === null ? "" : String(id))
}
/** the last workspace you had open, while it exists; else Machine; else the busiest */
function settleWorkspace() {
  if (!app.all.ok) return
  if (app.ws !== null && app.all.workspaces.some((w) => w.id === app.ws)) return
  app.ws = app.all.workspaces.find((w) => w.name.toLowerCase() === "machine")?.id ?? busiest(app.all)
}
function stepWs(d: 1 | -1) {
  const list = app.all.workspaces
  if (!list.length) return
  const i = list.findIndex((w) => w.id === app.ws)
  goWs(list[(i + d + list.length) % list.length]!.id)
}
function goWs(id: number) { choose(id); back(true); app.frame = null; void refresh() }

// ── staying current ───────────────────────────────────────────────────────────────────────────
// one refresh in flight and at most one queued: a write's follow-up reads what it wrote (tui/flight.ts)
const refresh = oneInFlight(refreshOnce)
async function refreshOnce() {
  for (const w of app.dumpSent.keys()) syncDump(w, true)
  // the snapshot lands, and shows, as soon as it comes: the inbox read beside it takes seconds (a git
  // check per stray worktree), and a finder opened meanwhile would list nothing
  const rest = Promise.all([data.needs(), data.settings()])
  app.all = await data.status()
  if (app.officeRev === undefined && app.all.ok) app.officeRev = app.all.revs?.office ?? null
  settleWorkspace()
  draw()
  let knobs: data.Settings | null
  ;[app.bySurface, knobs] = await rest
  app.needs = app.bySurface.items
  app.settings = knobs ?? app.settings
  if (app.all.ok && app.lastOk.ok) tellNews(app.lastOk, app.lastOkNeeds)
  if (app.all.ok) { app.lastOk = app.all; app.lastOkNeeds = app.needs; tickerOn(app.all) }
  const tid = openThread()
  await Promise.all([tid !== null ? loadThread(tid) : null, app.reader ? app.reader.reload() : null, loadCard(), loadFeed(), loadMargin()])
  await chatter()
  void tickLedger()
  draw()
}
/**
 * Scharlach's demerit ledger ticks when a coworker's build goes red. The sheriff's workspace's triage
 * carries each failed check's thread (whoever led it); a red first seen ticks, the same red held does
 * not, and one that clears then re-reds ticks again. Presentation only — it never touches the work.
 */
async function tickLedger() {
  if (!app.all.ok) return
  const sws = app.all.bench.find((c) => c.archetype === "sheriff")?.workspace_id
  if (sws == null) return
  const count = app.all.triage[String(sws)] ?? 0
  record(night(app.trophies, app.world ? app.world.now() : new Date(), count > 0))
  const t = count > 0 ? await data.triage(sws) : null
  if (count > 0 && !t) return
  const before = new Map(app.ledger.demerits)
  app.ledger = tickFromTriage(app.ledger, count, t?.failed_thread_ids ?? t?.failed_checks.shown.map((s) => s.thread_id) ?? [], app.all.threads)
  // rimworld: a red build sours that coworker's afternoon — room-local, the room's own reading of what it already saw
  for (const [who, n] of app.ledger.demerits) if (n > (before.get(who) ?? 0)) for (const r of app.rooms.values()) r.sourMood(who)
}
/** what changed since the last look that you'd want to hear about even with the office in the back */
function tellNews(before: Agents, beforeNeeds: data.Need[]) {
  // only an answer owed rings: a new item on the phone; several at once are one notification
  const was = new Set(beforeNeeds.map((n) => n.key))
  const fresh = app.bySurface.phone.filter((n) => !was.has(n.key))
  if (fresh.length) out("\x07") // something new waits on you: the terminal's bell
  if (fresh.length === 1) notify(needTitle(fresh[0]!), fresh[0]!.text)
  else if (fresh.length > 1) notify(`${fresh.length} things wait on you`, fresh.map(needTitle).join(" · "))
  if (before.health?.state === "ok" && app.all.health?.state === "warn") notify("tlon needs a look", app.all.health.problems.join("; "))
  for (const kind of arrivals(before, app.all, beforeNeeds, app.needs)) room().ring(kind)
  releaseOnTv(before, app.all)
}
/** the TV's ticker channel crawls the release, the merge queue, the phone and the newest landing's subject */
function tickerOn(a: Agents) {
  const t = { sha: a.release?.sha ?? null, queue: a.health?.merge_queue?.length ?? 0, phone: app.bySurface.counts.phone, last: lastLanding(a) }
  for (const r of app.rooms.values()) if (r instanceof WideRoom) r.setTicker(t)
}
/** a cut puts Uqbar's entry on the TV; the next snapshot that holds the same sha ends it */
function releaseOnTv(before: Agents, after: Agents) {
  if (!before.ok || !after.ok || !after.release) return
  for (const r of app.rooms.values()) {
    if (!(r instanceof WideRoom)) continue
    if (before.release?.sha !== after.release.sha) r.cut(after.release.sha, after.release.notes ?? [])
    else if (r.cutting) r.cutDone()
  }
}
/** a desktop notification (OSC 777, as ghostty, kitty, WezTerm and foot take it) */
function notify(title: string, body: string) {
  const clean = (s: string) => s.replace(/[;\x07\x1b]/g, " ").slice(0, 200)
  out(`${ESC}]777;notify;${clean(title)};${clean(body)}${ESC}\\`)
}
async function loadMargin() { app.notes = app.ws === null ? [] : await data.margin(app.ws) }
function record(next: Tally) {
  if (next === app.trophies) return
  for (const tr of newlyWon(app.trophies, next)) app.status = `trophy won: ${tr.name}`
  app.trophies = next
  writeState(TROPHY_FILE, serializeTally(next))
  for (const r of app.rooms.values()) if (r instanceof WideRoom) r.setTrophies(wonTrophies(next).length)
}
/** the tallies only the sim knows: a drill begun, treats given, a secret clock face */
function watchTrophies() {
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
  record(next)
}
async function loadFeed() {
  if (app.ws === null) return
  const first = !app.feed.length
  app.feed = (await data.activity(app.ws)) ?? app.feed
  const v = view(app), r = room()
  for (const x of freshPosts(app.feed, app.flown, first)) {
    if (r instanceof WideRoom && r.fly(x.thread_id!, v, handoffFrom(app.feed, x.thread_id!, Date.now()))) {
      app.earmarked.add(earmarkOf(x.thread_id!, x.at, x.who))
      record(bumpTally(app.trophies, "planes"))
      writeState(EARS, earmarksOut(app.earmarked))
    }
  }
  // a first run starts with the tray read, not with everything that ever happened in it
  if (!app.trayRead && app.feed[0]) { app.trayRead = app.feed[0].at; writeState(TRAY, app.trayRead) }
}
async function chatter() {
  if (app.ws === null) return
  const here = app.ws
  const dials = resolveWhim(app.whim), banter = dials.banter
  // the server writes these lines lazily, spending model tokens only when asked: with banter off, don't ask
  if (banter) room().hear(await data.pets(app.ws, room().petProfile()))
  // generated visitors, puns and reactions reach the room only past `curated`; the room ignores a pool it is not given
  room().setToys(dials.weirdness === "curated" ? null : await data.toys(here))
  // two together in the room: with souls on the server writes what they say now (from their souls), said turn by turn;
  // with them off, in --sandbox, or wherever the server wrote nothing, each says a canned line in their own voice
  room().onTogether = (situation, a, b) => !banter ? undefined : void (dials.souls ? data.talk(here, situation, a, b) : Promise.resolve([])).then((turns) => {
    const said = turns.length ? turns : [a, b].map((who) => {
      const recent = app.recentBanter.get(who) ?? []
      const line = seatLine(who, recent, situation)
      app.recentBanter.set(who, [line, ...recent].slice(0, 8))
      return { who, line }
    })
    room().converse(said); heard(said); changed(app)
  })
  app.cork = banter ? await data.corkboard(app.ws) : []
  room().pinboard(app.cork)
  app.ideas = await data.suggestions(app.ws)
  room().suggestionBox(app.ideas)
  // a conversation the server wrote arrives as lines sharing one `at`: said as one, turn by turn
  const convos = new Map<number, { who: string; line: string }[]>()
  for (const b of banter ? await data.banter(app.ws) : []) {
    const k = `${b.at} ${b.agent} ${b.line}`
    if (app.seenLines.has(k)) continue
    app.seenLines.add(k)
    convos.set(b.at, [...(convos.get(b.at) ?? []), { who: b.agent, line: b.line }])
  }
  if (banter) for (const turns of convos.values()) { room().converse(turns); heard(turns); changed(app) }
  await answers(app.ws)
}
async function answers(w: number) {
  const lobby = lobbyOf(view(app).threads, w)
  const v = lobby === null ? null : await data.thread(lobby)
  if (!v) return
  const fresh = replies(v.messages, operatorOf(app.all)).filter((r) => !app.answered?.has(r.id))
  const first = app.answered === null
  app.answered ??= new Set()
  for (const r of fresh) {
    app.answered.add(r.id)
    if (first) continue
    room().say(r.agent, r.line)
    if (app.mode.kind !== "home") notify(`${r.agent} answered`, r.line)
    changed(app)
  }
}
async function loadThread(tid: number) { const v = await data.thread(tid); if (v) app.threads.set(tid, v) }
/** the open card's own read, if it has one */
async function loadCard() {
  if (app.ws === null) return
  const w = app.ws
  const key = cardKey(app.mode)
  const why = await data.reading(() => readCard(w))
  if (why) app.readWhys.set(key, why); else app.readWhys.delete(key)
}
async function readCard(w: number) {
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
/** after a write: say what happened, then look again */
async function did(p: Promise<string>) { app.status = await p; if (app.reader) app.reader.status = app.status; await refresh() }

/** the thread the detail pane is showing, if any */
function openThread(): number | null {
  if (app.reader) return app.reader.tid
  if (app.mode.kind === "thread") return app.mode.tid
  if (app.mode.kind === "person") { const name = app.mode.name, p = crewOf(view(app)).find((c) => c.name === name); return p?.thread ?? null }
  return null
}
function open(m: Mode) {
  if ((m.kind === "person" || m.kind === "thread" || m.kind === "look" || m.kind === "review" || m.kind === "issue" || m.kind === "play") && m.from === undefined && app.mode.kind !== "home" && app.mode.kind !== "help" && app.mode.kind !== m.kind) m = { ...m, from: app.mode }
  app.status = ""; app.readWhys.delete(cardKey(m)); app.mode = m; app.sel = 0; app.scroll = m.kind === "thread" || m.kind === "person" ? Infinity : 0; app.confirm = null; app.picker = null; app.snapSel = true
  if (m.kind === "thread") { app.picked = m.tid; app.cardReply = { tid: m.tid, ed: app.cardReply?.tid === m.tid ? app.cardReply.ed : new Editor(), focused: !asks(m.tid) } }
  if (m.kind === "person") app.cardOpen = false
  if (m.kind === "person") app.picked = crewOf(view(app)).find((c) => c.name === m.name)?.thread ?? null
  if (m.kind === "pet" && m.who === "cat") { app.petDraft = structuredClone((app.petsNow ?? resolvePets(loadPets())).cat); app.previewTick = 0 }
  if (m.kind === "look") app.lookDraft = m.hall ? structuredClone(candidateOf(app.hall, hallCtx(app)).look) : { ...baseLook(m.name), ...overrideFor(m.name) }
  const tid = openThread()
  void Promise.all([tid !== null ? loadThread(tid) : null, loadCard()]).then(draw)
  draw()
}
/** Esc: a card back to the card it was opened from, else home; home to nothing picked; `all` drops both at once */
function back(everything = false) {
  const from = !everything && app.mode.kind !== "help" && "from" in app.mode ? app.mode.from : undefined
  app.status = ""
  if (everything || app.mode.kind === "home") app.picked = null
  app.mode = from ?? { kind: "home" }; app.sel = 0; app.scroll = 0; app.confirm = null; app.picker = null; app.lookDraft = null; app.petDraft = null
}

function act(x: Act) {
  switch (x.kind) {
    case "thread": return open({ kind: "thread", tid: x.tid })
    case "ticket": return open({ kind: "ticket", id: x.id })
    case "epic": return open({ kind: "epic", id: x.id })
    case "person": return open({ kind: "person", name: x.name })
    case "column": return open({ kind: "column", col: x.col })
    case "notes": return open({ kind: "notes" })
    case "crew": return open({ kind: "crew" })
    case "boss": return open({ kind: "boss" })
    case "hire": return hire()
    case "pen": return newTicket()
    case "cat": room().pet(); changed(app); return open({ kind: "pet", who: "cat" })
    case "calendar": return open({ kind: "calendar" })
    case "terminal": return void zoomInto(x.tid)
    case "archive": return open({ kind: "archive" })
    case "tray": return open({ kind: "tray" })
    case "beacon": return open({ kind: "triage" })
    case "machine": return hearMachine()
    case "clipboard": return open({ kind: "needs" })
    case "needs": return inbox()
    case "rack": return open({ kind: "health" })
    case "dog": { const r = room(); if (r instanceof WideRoom) r.patDog(); changed(app); return open({ kind: "pet", who: "dog" }) }
    case "tv": { const r = room(); if (r instanceof WideRoom) { r.channel(); changed(app); draw() } return }
    case "arcade": return open({ kind: "arcade" })
    case "ideas": return open({ kind: "ideas" })
    case "weather": app.status = app.all.weather ? `outside: ${app.all.weather.desc.toLowerCase()}${app.all.weather.temp_c === null ? "" : `, ${app.all.weather.temp_c}°C`}` : "no word on the weather"; return draw()
  }
}

// ── writing: the inputs ─────────────────────────────────────────────────────────────────────────
function ask(label: string, submit: Prompt["submit"], opts: { multiline?: boolean; text?: string; cycles?: Cycle[] } = {}) {
  const held = app.banked.get(label)
  app.banked.delete(label)
  app.input = { label, ed: new Editor(held ?? opts.text ?? "", !!opts.multiline), submit, cycles: opts.cycles, focus: 0 }
  draw()
}
function newThread() {
  if (app.ws === null) return
  const w = app.ws, projects = view(app).projects
  ask("new thread — your first words; the first line is its title", (s, [project, kind]) => { if (s.trim()) did(data.newThread(w, s.trim(), project as number | null, kind as data.Kind)) }, {
    multiline: true,
    cycles: [
      { name: "project", values: [{ label: "the default project", value: null }, ...projects.map((p) => ({ label: p.name, value: p.id }))], i: 0 },
      { name: "as", values: [{ label: "a thread", value: "thread" }, { label: "a workline (from intent)", value: "workline" }, { label: "a spike (straight to build)", value: "spike" }], i: 0 },
    ],
  })
}
function newTicket() {
  if (app.ws === null) return
  const w = app.ws
  ask("new ticket", (s) => { if (s.trim()) did(data.ticketFile(w, s.trim())) })
}
function newNote() {
  if (app.ws === null) return
  const w = app.ws
  ask("a note for the corkboard", (s) => { if (s.trim()) did(data.note(w, s.trim())) }, { multiline: true })
}
/** speak to a coworker (`to`) or, with null, to the office — the speech composer */
function talk(to: string | null) {
  if (app.ws === null) return
  const w = app.ws
  // every thread, not the workspace's view: uqbar's study may live on another workspace
  const label = to ? `say to ${to}` : "say to the office"
  ask(label, (s) => {
    const sent = say(app.all.threads, w, to, s)
    // a post that did not go keeps its words: `'` brings them back
    void sent.then((line) => { if (s.trim() && !data.landed(line)) app.banked.set(label, s) })
    void did(sent)
  }, { multiline: true })
}
function reply(tid: number) {
  const box = cardBox(app)
  if (box?.tid === tid) { box.focused = true; return draw() }
  openReader(tid)
}
/** a key while a thread card's reply box has focus: Enter sends, Esc leaves the box (the card stays) */
function boxKey(box: NonNullable<typeof app.cardReply>, k: string) {
  if (k === "esc") { box.focused = false; return draw() }
  if (k === "enter") {
    if (box.ed.empty) return
    const body = box.ed.text
    box.ed = new Editor(); app.scroll = Infinity
    const sent = data.post(box.tid, body)
    // a post that did not go puts the words back in the box, ahead of anything typed since
    void sent.then((line) => { if (!data.landed(line)) box.ed = new Editor(box.ed.empty ? body : `${body}\n${box.ed.text}`) })
    void did(sent)
    return draw()
  }
  if (k === "pgup" || k === "pgdn") return page(k === "pgdn" ? 1 : -1)
  box.ed.key(k)
  draw()
}
function hire() {
  if (app.ws === null) return
  const w = app.ws, kinds = app.all.archetypes.map((x) => ({ label: `${x.name}${x.meta ? " (manager)" : x.read_only ? " (read-only)" : ""}`, value: x.name }))
  if (!kinds.length) { app.status = "no archetypes to hire from"; return draw() }
  ask("hire — their name", (s, [arch]) => { if (s.trim()) did(data.hire(w, s.trim(), arch as string)) }, { cycles: [{ name: "as", values: kinds, i: Math.max(0, kinds.findIndex((k) => k.value === "builder")) }] })
}

// ── the finder ─────────────────────────────────────────────────────────────────────────────────
function find(title: string, items: Pick[]) { app.picker = { title, q: new Editor("", false), items, sel: 0 }; draw() }
/** open a thread wherever it lives, switching workspace first */
function goThread(id: number, wsId: number | null | undefined) {
  if (wsId != null && wsId !== app.ws) { choose(wsId); app.frame = null }
  app.picker = null
  openReader(id)
}
async function finder() {
  const picks: Pick[] = []
  for (const t of app.all.threads) {
    const where = wsName(app, t.workspace_id ?? null)
    picks.push({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, { s: `  ${where}${t.lead ? ` · ${t.lead}` : ""}${needsYou(t) ? " · waiting on you" : ""}`, fg: needsYou(t) ? ROLE.attention : ROLE.inactive }], text: `#${t.id} ${t.title} ${where} ${t.lead ?? ""}`, run: () => goThread(t.id, t.workspace_id) })
  }
  picks.push(...ticketPicks(app.all.tickets, (id) => wsName(app, id), (id) => open({ kind: "ticket", id })))
  for (const w of app.all.workspaces) picks.push({ segs: [{ s: "workspace ", fg: ROLE.inactive }, { s: w.name, fg: ROLE.body }], text: `workspace ${w.name}`, run: () => goWs(w.id) })
  for (const c of app.all.bench.filter((b) => b.workspace_id === app.ws)) picks.push({ segs: [{ s: "coworker ", fg: ROLE.inactive }, { s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}`, fg: ROLE.inactive }], text: `${c.name} ${c.archetype}`, run: () => open({ kind: "person", name: c.name }) })
  const toyVerbs: [string, () => void][] = app.world ? [["cut a release (the toy: Uqbar's entry on the TV)", () => { app.world!.cut(); app.status = "a cut: pizza at the door, the entry on the TV"; void refresh() }]] : []
  for (const [label, run] of [...VERBS, ...toyVerbs]) picks.push({ segs: [{ s: "do ", fg: ROLE.inactive }, { s: label, fg: ROLE.prose }], text: label, run })
  picks.push({ segs: [{ s: "the Library of Babel", fg: ROLE.inactive }], text: "babel library borges", run: () => openBabel() })
  find("FIND — a thread, a workspace, a coworker, a verb", picks)
  const closed = await data.history()
  if (app.picker?.title.startsWith("FIND") && closed) {
    for (const t of closed) app.picker.items.push({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.inactive }, { s: `  closed ${t.at.slice(0, 10)}`, fg: ROLE.inactive }], text: `#${t.id} ${t.title} closed`, run: () => goThread(t.id, t.workspace_id) })
    draw()
  }
}
/** everything across the workspaces that waits on you, then what's being worked on */
/** a page of the Library of Babel, the width of the card */
function openBabel() {
  const page = babelPage(DETAIL - 2, Math.max(20, paneW() - 4))
  if (hasFound(page)) record(findSecret(app.trophies, "babel"))
  open({ kind: "babel", page })
}

/** what waits on you: one at a time when anything does — the whole list is a key away */
function inbox() { open(app.needs.length ? { kind: "decide", i: 0 } : { kind: "needs" }) }
/** the answering machine played: the inbox opens, and what was on the machine is heard */
function hearMachine() {
  const keys = app.bySurface.machine.map((n) => n.key)
  open({ kind: "needs" })
  if (keys.length) void did(data.hear(keys))
}
const needTitle = (n: data.Need) => `${NEED_KIND[n.kind]}${n.thread_id ? ` #${n.thread_id}` : ""} — ${n.title}`
/** main's office has moved past the revision this TUI started on */
const updated = () => !!app.officeRev && !!app.all.revs?.office && app.all.revs.office !== app.officeRev

/** the verbs the finder offers by name — the same ones the keys reach */
const VERBS: [string, () => void][] = [
  ["new thread", () => newThread()], ["new ticket", () => newTicket()], ["new note", () => newNote()], ["hire a coworker", () => hire()],
  ["in-tray: what just happened", () => open({ kind: "tray" })], ["triage: what is stuck", () => open({ kind: "triage" })],
  ["health: the service and its box", () => open({ kind: "health" })], ["memory: pinned facts and habits", () => open({ kind: "memory" })],
  ["workspaces", () => open({ kind: "boss" })], ["this workspace's settings and repos", () => open({ kind: "card" })],
  ["settings: the running system's knobs", () => open({ kind: "settings" })], ["restart the server (waits for quiet)", () => void did(data.restart())],
  ["the wackiness dial: business … rimworld", () => open({ kind: "whimsy" })],
  ["crew", () => open({ kind: "crew" })], ["shifts", () => open({ kind: "crew" })], ["calendar", () => open({ kind: "calendar" })], ["tickets & worklines: the board", () => open({ kind: "column", col: 0 })], ["filing cabinet", () => open({ kind: "archive" })],
  ["inbox: everything waiting on you", () => inbox()], ["schedule something", () => newSchedule(app, ctl)],
  ["pencils down: nothing new, everyone stops after their turn", () => void did(data.pause("pencils_down"))],
  ["lights out: stop everyone now", () => ask2("lights out — pause verify and landing, interrupt every pane", () => void did(data.pause("lights_out")))],
  ["back to work", () => void did(data.pause("back_to_work"))],
  ["Nina, the cat", () => open({ kind: "pet", who: "cat" })], ["Argos, the dog", () => open({ kind: "pet", who: "dog" })],
  ["the arcade", () => open({ kind: "arcade" })], ["the suggestion box", () => open({ kind: "ideas" })],
  ["the banter log: what the crew said lately", () => open({ kind: "banter" })],
  ["trophies: what the office has earned", () => open({ kind: "trophies" })],
  ["Uqbar's entry — the office as a page", () => open({ kind: "entry" })],
]

// ── the reader: a thread full-screen ────────────────────────────────────────────────────────────
function openReader(tid: number, extra: Partial<ReaderDeps> = {}, focus = !asks(tid)) {
  app.picked = tid
  app.reader = new Reader(tid, { load: (before) => (before ? data.page(tid, before) : data.thread(tid)), send: (body) => data.post(tid, body), operator: operatorOf(app.all), redraw: () => draw(), dogeared: (m) => app.earmarked.has(earmarkOf(tid, m.at, m.author)), ...extra }, focus, app.cardReply?.tid === tid ? app.cardReply.ed.text : "")
  if (app.cardReply?.tid === tid) app.cardReply = null
  const v = app.threads.get(tid)
  if (v) app.reader.take(v)
  void app.reader.reload().then(draw)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
  draw()
}
/** the conversation with `name`: the lobby filtered to them and the operator's words to them; a reply goes to them */
function openConversation(name: string) {
  const lobby = lobbyOf(view(app).threads, app.ws)
  if (lobby === null) { app.status = "no front desk in this workspace"; return draw() }
  openReader(lobby, {
    keep: (ms) => conversation(ms, name, operatorOf(app.all)),
    heading: `conversation with ${name}`,
    send: (body) => data.post(lobby, speech(name, body) ?? body),
  })
}
/** the reader's draft goes back to the thread's box, so its card or the next reader starts from it */
function bankReader() {
  const held = app.reader?.held()
  if (app.reader && held) app.cardReply = { tid: app.reader.tid, ed: new Editor(held), focused: true }
}
function closeReader() {
  bankReader()
  app.reader = null
  out(`${ESC}[?25l`)
  layoutScreen(); draw()
}
const ask2 = (label: string, run: () => void) => { app.confirm = { label, run }; draw() }

// ── the detail pane ────────────────────────────────────────────────────────────────────────────

const back1: Action = { ...bind("back.esc"), run: () => { back(); app.roomChanged = true; draw() } }

// ── drawing ────────────────────────────────────────────────────────────────────────────────────
function layoutScreen() {
  const colsN = cols(), rowsN = process.stdout.rows ?? 40
  // as wide as the terminal, at the biggest whole scale (2 at least) that both fits its height and
  // leaves the room wide enough for its zones
  let next: number | null = null
  if (app.kitty && app.cell) {
    for (let k = Math.min(5, Math.floor(((rowsN - DETAIL - 3) * app.cell.h) / WIDE_H)); k >= 2 && next === null; k--) {
      const w = Math.floor((colsN * app.cell.w) / k)
      if (w >= WIDE_MIN_W) next = w
    }
  } else if (process.env.OFFICE_WIDE) {
    // half blocks have no cell size to ask for, so a drive opts in: the wide room at whatever scale fits the window
    next = Math.max(WIDE_MIN_W, Math.floor(colsN / Math.max(0.25, ((rowsN - DETAIL - 3) * 2) / WIDE_H)))
  }
  if (next !== app.wide) { app.wide = next; app.rooms.clear() }
  app.g = { ...(app.wide ? geometry(app.wide, (r0 => (r0 instanceof WideRoom ? r0.height : WIDE_H))(room()), colsN, rowsN, DETAIL + 3, app.cell, app.kitty, WIDE_H) : geometry(W, H, colsN, rowsN, DETAIL + 3, app.cell, app.kitty)), row: 1 }
  const vw = Math.min(app.g.floorW, (app.g.cols * app.g.cw) / app.g.k), vh = Math.min(app.g.floorH, (app.g.rows * app.g.ch) / app.g.k)
  app.viewport = app.follow
    ? centerViewport({ x: 0, y: 0, w: vw, h: vh }, OFF_W / 2, (BAND + OFF_DOOR) / 2, app.g.floorW, app.g.floorH)
    : centerViewport({ ...app.viewport, w: vw, h: vh }, app.viewport.x + app.viewport.w / 2, app.viewport.y + app.viewport.h / 2, app.g.floorW, app.g.floorH)
  app.frame = null; app.sentImage = false
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
}

/** `roomOnly`: the room's clock moved and nothing else did — repaint the room and its tip, leave the header and the pane as the last full draw made them */
function draw() { paint(false) }
function paint(roomOnly: boolean) {
  if (!app.g || app.zoom) return
  const colsN = cols(), termRows = process.stdout.rows ?? 40
  if (app.reader) {
    app.paneCursor = null
    if (app.picker || app.confirm) { out(`${ESC}[?25l` + drawOverlay(colsN, termRows)); return }
    out(app.reader.draw(colsN, termRows, threadOf(app, app.reader.tid), [...threadActions(app, ctl, app.reader.tid, true).map((x) => `${x.key} ${x.label}`), "pgup/pgdn scroll", "esc back", "ctrl+] room"].join(" · ")))
    return
  }
  const a = view(app)
  const partial = roomOnly && app.paneCursor !== null
  let o = `${ESC}[?2026h${ESC}[?25l`
  // header: the workspace, and what waits elsewhere
  if (!partial) {
    const phone = phoneBar(app.bySurface.counts), usage = usageHeader(app.all, Date.now())
    const head: (Seg & { go?: () => void })[] = [{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(app), fg: ROLE.body, bold: true }, key(" › "),
      ...(app.all.ok ? [] : [{ s: `  ${downHeader(app.all, Date.now())}`, fg: ROLE.alarm }]),
      ...(phone ? badge({ s: `  ${ringFrame(Math.floor(Date.now() / 1000), phone.ringing)} ${phone.text} `, fg: ROLE.ground, bg: ROLE.attention, bold: true, go: inbox }) : []),
      ...(shiftHeader() ? [{ s: `  ${shiftHeader()}`, fg: ROLE.body, go: toggleShift }] : []),
      ...(app.all.pause === "pencils_down" || app.all.pause === "lights_out" ? badge({ s: app.all.pause === "lights_out" ? "  ◼ lights out " : "  ✎ pencils down ", fg: ROLE.ground, bg: ROLE.attention, bold: true, go: () => ask2("back to work", () => void did(data.pause("back_to_work"))) }) : []),
      ...(queuesHeader() ? [{ s: `  ${queuesHeader()}`, fg: ROLE.live, go: () => open({ kind: "health" }) }] : []),
      ...(lifeHeader(app.all, app.ws) ? [{ s: `  ${lifeHeader(app.all, app.ws)}`, fg: ROLE.body }, dim("  (L)")] : []),
      ...(usage ? [{ s: `  ${usage.text}`, fg: usage.hot ? ROLE.attention : ROLE.body, bold: usage.hot }] : []),
      ...(updated() ? [{ s: "  office updated · R reloads", fg: ROLE.live, bold: true }] : []),
      ...(app.all.health?.state === "warn" ? [{ s: `  ⚠ ${app.all.health.problems[0]}`, fg: ROLE.alarm, go: () => open({ kind: "health" }) }] : []),
      ...(process.env.OFFICE_DEBUG ? [dim(`  viewport ${Math.round(app.viewport.x)},${Math.round(app.viewport.y)}`)] : [])]
    app.headHits = []
    let hx = 1
    for (const s of head) { const w = cells(s.s); if (s.go) app.headHits.push({ from: hx, to: hx + w - 1, go: s.go }); hx += w }
    o += `${ESC}[1;1H` + line(head, colsN)
  }
  // the room
  const room0 = room()
  const building = app.mode.kind === "build" && app.build !== null
  const fresh = !app.frame
  // leaving build mode puts the room back, however the mode was left
  if (!building && app.homeShown) {
    app.roomChanged = true; app.imageDirty = true
    app.homeNow = loadFloor()
    for (const r of app.rooms.values()) if (r instanceof WideRoom) { r.setHome(app.homeNow); r.setStreaks(streakFrames(app.lifeCard?.streaks ?? {})) }
    // the home below the office grows or shrinks with the home, and the room's rows with it
    layoutScreen()
  }
  app.homeShown = building
  const vp = building ? { x: 0, y: 0, w: app.viewport.w, h: app.viewport.h } : app.viewport
  if (building) {
    app.frame = renderHome({ top: app.build!.top, home: app.build!.home, cursor: app.build!.cursor, carrying: app.build!.carrying, refused: app.build!.refused, w: Math.ceil(vp.w), h: Math.ceil(vp.h), weather: a.weather?.kind, mail: mailbox(app.needs), frames: streakFrames(app.lifeCard?.streaks ?? {}), bed: bedScene(app.lifeCard?.today ?? [], Date.now()) })
    app.imageDirty = true
  } else if (fresh || app.roomChanged) { app.frame = room0.render(a, { picked: app.lit ?? app.picked, person: app.mode.kind === "person" ? app.mode.name : null, tray: unread(), board: boardCtx(app), machine: app.bySurface.counts.machine, clipboard: app.bySurface.clipboard.filter((n) => n.workspace_id == null || n.workspace_id === app.ws) }, measureFor(app.g), app.world?.now()); app.roomChanged = false }
  const seen = clipFrame(app.frame!, vp)
  if (!building) addMargin(seen, vp)
  if (app.g.kitty && (!app.sentImage || fresh || app.imageDirty || app.panned)) { o += kittyImage(seen, app.g, vp); app.sentImage = true; app.imageDirty = false }
  if (!app.g.kitty) textLayer(seen, app.g, vp).forEach((l, i) => { o += `${ESC}[${app.g.row + 1 + i};${app.g.col + 1}H${l}` })
  app.panned = false
  // the tip line: what the pointer is over, or what just happened
  const tipRow = app.g.row + app.g.rows + 1
  o += `${ESC}[${tipRow};1H` + line([app.tip ? dim(` ${app.tip.split("\n").join(" · ")}`) : app.status ? key(` ${app.status}`) : dim("")], colsN)
  if (partial) return out(o + app.paneCursor + `${ESC}[?2026l`)
  const pane = drawPane(tipRow + 1, colsN, termRows)
  app.paneCursor = /\x1b\[\d+;\d+H\x1b\[\?25h$/.exec(pane)?.[0] ?? ""
  out(o + pane + `${ESC}[?2026l`)
}

/** the actions take j/k and enter when the card's rows have nothing to open */
const actionsFocused = () => !app.rows.some((r) => r.open)
/** the keys that work everywhere a card's own actions don't claim them */
const GLOBALS: Hint[] = hints("global")
/** a window's line `i`, as a row index, an "↑ N more" (-1) or "↓ N more" (-2), or nothing */
function lineOf(w: Window, i: number): number | undefined {
  if (w.above && i === 0) return -1
  const j = i - (w.above ? 1 : 0)
  if (j < w.count) return w.first + j
  if (w.below && j === w.count) return -2
  return undefined
}
const more = (w: Window, at: number, how: string): Seg[] => [dim(at === -1 ? `  ↑ ${w.above} more${how}` : `  ↓ ${w.below} more${how}`)]
const fit = (s: string, w: number) => (cells(s) <= w ? s : `${[...s].slice(0, Math.max(0, w - 1)).join("")}…`)

/** the pane from row `top` to the foot: the finder, a multi-line input, or the card — its rows on the left, its actions on the right */
function drawPane(top: number, colsN: number, termRows: number): string {
  let o = `${ESC}[?7l`
  let title: string, keys = "", segRows: Row[], cursor: { r: number; c: number } | null = null
  let tint = ROLE.key
  app.acts = []
  if (app.picker) {
    const shown = rank(app.picker.q.text, app.picker.items, (p) => p.text)
    app.picker.sel = Math.min(app.picker.sel, Math.max(0, shown.length - 1))
    title = `${app.picker.title}: ${app.picker.q.text}`
    segRows = shown.map((p) => ({ segs: p.segs, open: p.run }))
    keys = "type to narrow · ↑↓ move · enter pick · esc close · ctrl+] room"
    cursor = { r: -1, c: title.length + 1 }
    app.sel = app.picker.sel
  } else if (app.input?.ed.multiline) {
    const v = app.input.ed.view(colsN - 6, Math.max(1, termRows - top - 3))
    title = app.input.label
    segRows = [{ segs: cyclesSegs(app.input) }, ...v.rows.map((r) => ({ segs: [pink(" ▌ "), plain(r)] }))]
    keys = `enter done · alt-enter newline${app.input.cycles?.length ? ` · tab change the lit choice${app.input.cycles.length > 1 ? " · shift-tab the next choice" : ""}` : ""} · esc cancel · ctrl+] room`
    cursor = { r: v.cursor.r + 1, c: v.cursor.c + 3 }
  } else {
    const d = detail(app, ctl)
    const add = adder(`card:${app.mode.kind}`)
    title = d.title; app.acts = d.actions; tint = d.tint ?? ROLE.key
    segRows = d.rows.length ? d.rows : [{ segs: [dim(`nothing here yet${add ? ` — ${keyName(add.key)} ${add.label}` : ""}`)] }]
  }
  app.rows = segRows
  const split = app.acts.length > 0 && colsN >= 80
  const leftW = split ? colsN - ACTIONS_W - 1 : colsN
  const box = app.picker || app.input ? null : cardBox(app), bv = box?.ed.view(leftW - 4, 4), boxH = bv ? bv.rows.length + 1 : 0
  if (box?.focused) keys = "enter send · alt-enter newline · esc leave the box · pgup/pgdn scroll · ctrl+] room"
  const selectable = app.rows.some((r) => r.open) && !app.input
  if (app.snapSel && selectable && !app.picker) { app.snapSel = false; if (!app.rows[app.sel]?.open) app.sel = app.rows.findIndex((r) => r.open) }
  if (app.sel >= app.rows.length) app.sel = Math.max(0, app.rows.length - 1)
  if (app.asel >= app.acts.length) app.asel = Math.max(0, app.acts.length - 1)
  // the foot lists what the actions column can't show (all of it, with no column), then the globals;
  // its height and the column's room depend on each other, so settle them together
  const claimed = new Set(app.acts.map((x) => x.key))
  const globals = [...(app.world ? PLAY : []), ...GLOBALS.filter((h) => !h.key.split(" ").some((k) => claimed.has(k)))]
  let footN = 1, room = 0, win: Window, awin: Window = { first: 0, count: 0, above: 0, below: 0 }, foot: Hint[][] = []
  for (let pass = 0; pass < 3; pass++) {
    room = Math.max(1, termRows - footN - 1 - top - boxH)
    win = cursor && app.input ? offset(app.rows.length, room, 0) : selectable || app.picker ? followSel(app.rows.length, app.sel, room) : offset(app.rows.length, room, app.scroll)
    if (split) awin = !selectable ? followSel(app.acts.length, app.asel, room) : offset(app.acts.length, room, 0)
    const hidden = split ? app.acts.filter((_, i) => i < awin.first || i >= awin.first + awin.count) : app.acts
    foot = keys ? [] : footLines([...hidden.map((x) => ({ key: keyName(x.key), label: x.label })), ...globals], colsN - 2, Math.max(1, Math.floor((termRows - top - 1) / 2)))
    const n = Math.max(1, foot.length)
    if (n === footN) break
    footN = n
  }
  win = win!
  if (!selectable && !app.picker && !app.input && Number.isFinite(app.scroll)) app.scroll = win.first
  const bar = (t: string, w: number, bg: string) => line([{ s: ` ${t} `, fg: ROLE.ground, bg }, dim(" " + "─".repeat(Math.max(0, w - cells(t) - 3)))], w)
  o += `${ESC}[${top};1H` + bar(title, leftW, app.picker || app.input ? ROLE.attention : tint) + (split ? line([dim("┬")], 1) + bar("ACTIONS", ACTIONS_W, ROLE.key) : "")
  const how = selectable || app.picker ? "" : " · pgup/pgdn"
  app.pane = { top, leftW, room, first: win.first, rowAt: [], actAt: [] }
  for (let i = 0; i < room; i++) {
    const at = lineOf(win, i), r = at !== undefined && at >= 0 ? app.rows[at] : undefined
    app.pane.rowAt.push(r ? at : undefined)
    const mark = r && selectable && at === app.sel && app.mode.kind !== "thread" && app.mode.kind !== "person" ? key("▸ ") : plain("  ")
    o += `${ESC}[${top + 1 + i};1H` + line(r ? [mark, ...r.segs] : at !== undefined ? more(win, at, how) : [], leftW)
    if (split) {
      const ai = lineOf(awin, i), x = ai !== undefined && ai >= 0 ? app.acts[ai] : undefined
      app.pane.actAt.push(x ? ai : undefined)
      const lit = x && !selectable && ai === app.asel
      o += `${ESC}[${top + 1 + i};${leftW + 1}H` + line([dim("│")], 1) + line(x ? [lit ? key("▸") : plain(" "), { s: ` ${keyName(x.key).padStart(5)} `, fg: ROLE.key, bold: true }, { s: fit(x.label, ACTIONS_W - 8), fg: x.key === "esc" ? ROLE.inactive : ROLE.prose }] : ai !== undefined ? more(awin, ai, selectable ? " · in the foot" : "") : [], ACTIONS_W)
    }
  }
  const boxAt = top + 1 + room
  if (box && bv) {
    const on = box.focused
    o += `${ESC}[${boxAt};1H` + line([{ s: " reply ", fg: ROLE.ground, bg: on ? ROLE.attention : ROLE.inactive }, dim(on ? "" : `  r${app.acts.some((x) => x.key === "enter") ? "" : " or ⏎"} to write`)], leftW)
    bv.rows.forEach((r, i) => { o += `${ESC}[${boxAt + 1 + i};1H` + line([on ? pink(" ▌ ") : dim(" ▌ "), on ? plain(r) : dim(r)], leftW) })
    if (split) for (let i = 0; i < boxH; i++) o += `${ESC}[${boxAt + i};${leftW + 1}H` + line([dim("│")], 1) + line([], ACTIONS_W)
  }
  // the foot: what you are typing, a confirm, or the keys — the lit one when the actions have them and no column shows it
  o += `${ESC}[${termRows - footN};1H` + line([], colsN)
  const one = app.input && !app.input.ed.multiline ? app.input : null
  const litKey = !split && !selectable && app.acts[app.asel] ? keyName(app.acts[app.asel]!.key) : null
  const hintSegs = (l: Hint[]): Seg[] => l.flatMap((h, j): Seg[] => [...(j ? [dim(" · ")] : []), h.key === litKey ? { s: `${h.key} ${h.label}`, fg: ROLE.ground, bg: ROLE.key } : { s: h.key, fg: ROLE.key, bold: true }, ...(h.key === litKey ? [] : [plain(` ${h.label}`)])])
  const feet: Seg[][] = one ? [[pink(` ${one.label}: `), plain(one.ed.text), ...(one.cycles?.length ? [dim("   tab: "), ...cyclesSegs(one)] : [])]] : app.confirm ? [[pink(` ${app.confirm.label} (y/n) · enter is y`)]] : keys ? [[dim(` ${keys}`)]] : foot.map((l) => [plain(" "), ...hintSegs(l)])
  for (let i = 0; i < footN; i++) o += `${ESC}[${termRows - footN + 1 + i};1H` + line(feet[i] ?? [], colsN)
  o += `${ESC}[?7h`
  if (one) {
    const pre = [...` ${one.label}: `].length
    o += `${ESC}[${termRows};${pre + one.ed.col + 1}H${ESC}[?25h`
  } else if (box?.focused && bv && !app.confirm) o += `${ESC}[${boxAt + 1 + bv.cursor.r};${4 + bv.cursor.c}H${ESC}[?25h`
  else if (cursor && cursor.r >= 0) o += `${ESC}[${top + 1 + cursor.r};${cursor.c + 3}H${ESC}[?25h`
  else if (cursor) o += `${ESC}[${top};${cursor.c + 1}H${ESC}[?25h`
  return o
}

const cyclesSegs = (i: Prompt): Seg[] => (i.cycles ?? []).flatMap((c, n) => [dim(`${c.name} `), n === i.focus && (i.cycles?.length ?? 0) > 1 ? { s: `‹${c.values[c.i]!.label}› `, fg: ROLE.ground, bg: ROLE.key } : key(`‹${c.values[c.i]!.label}› `)])

/** the finder or a confirm over the reader: drawn in the bottom rows, the conversation above */
function drawOverlay(colsN: number, termRows: number): string {
  const top = Math.max(2, termRows - DETAIL - 1)
  let o = `${ESC}[?2026h`
  for (let r = top; r <= termRows; r++) o += `${ESC}[${r};1H` + line([], colsN)
  return o + drawPane(top, colsN, termRows) + `${ESC}[?2026l`
}

// ── input ──────────────────────────────────────────────────────────────────────────────────────
function inputKey(k: string) {
  const i = app.input!
  if (k === "esc") { app.input = null; return draw() }
  if (k === "enter") { app.input = null; i.submit(i.ed.text, (i.cycles ?? []).map((c) => c.values[c.i]!.value)); return draw() }
  if ((k === "tab" || k === "backtab") && i.cycles?.length) {
    if (k === "backtab") i.focus = (i.focus + 1) % i.cycles.length
    else { const c = i.cycles[i.focus]!; c.i = (c.i + 1) % c.values.length }
    return draw()
  }
  i.ed.key(k)
  draw()
}
function pickerKey(k: string) {
  const p = app.picker!
  const shown = rank(p.q.text, p.items, (x) => x.text)
  if (k === "esc") { app.picker = null; return draw() }
  if (k === "enter") { const it = shown[p.sel]; app.picker = null; it?.run(); return draw() }
  if (k === "down" || k === "ctrl-n" || k === "tab") { p.sel = Math.min(p.sel + 1, shown.length - 1); return draw() }
  if (k === "up" || k === "ctrl-p" || k === "backtab") { p.sel = Math.max(p.sel - 1, 0); return draw() }
  if (p.q.key(k)) p.sel = 0
  draw()
}

function paintAt(ch: string) {
  if (app.mode.kind !== "look-editor" || !app.editBuf) return
  const view = app.mode.view, row = app.editBuf[view]![app.editCursor.y]!.split("")
  row[app.editCursor.x] = ch
  if (app.editMirror) row[11 - app.editCursor.x] = ch
  app.editBuf[view]![app.editCursor.y] = row.join("")
  draw()
}

function editorKey(k: string) {
  if (app.mode.kind !== "look-editor" || !app.editBuf) return
  const { name, view } = app.mode
  if (k === "up") { app.editCursor.y = Math.max(0, app.editCursor.y - 1); return draw() }
  if (k === "down") { app.editCursor.y = Math.min(21, app.editCursor.y + 1); return draw() }
  if (k === "left") { app.editCursor.x = Math.max(0, app.editCursor.x - 1); return draw() }
  if (k === "right") { app.editCursor.x = Math.min(11, app.editCursor.x + 1); return draw() }
  if (k === "m") { app.editMirror = !app.editMirror; return draw() }
  if (k === "1" || k === "2" || k === "3") {
    app.mode = { kind: "look-editor", name, view: k === "1" ? "front" : k === "2" ? "side" : "back", from: app.mode.from, hall: app.mode.hall }
    return draw()
  }
  if (k === "esc") {
    if (app.editEntry) app.editBuf[view] = [...app.editEntry[view]]
    app.mode = { kind: "look", name, from: app.mode.from, hall: app.mode.hall }; app.sel = 0; app.snapSel = true; return draw()
  }
  if (k === "enter") {
    if (app.lookDraft) {
      const custom = trimCustom(app.editBuf)
      if (custom) app.lookDraft.custom = custom
      else delete app.lookDraft.custom
    }
    app.mode = { kind: "look", name, from: app.mode.from, hall: app.mode.hall }; app.sel = 0; app.snapSel = true; return draw()
  }
  if (k === ".") return paintAt(".")
  if ((LEGEND_CHARS as readonly string[]).includes(k)) return paintAt(k)
}

/** the help card over the card you are on: its keys, the globals, the reader's and, in the sandbox, the play keys */
function help() {
  if (app.mode.kind === "help") return
  const d = detail(app, ctl)
  open({ kind: "help", from: app.mode, title: d.title, keys: d.actions.map((x) => ({ key: keyName(x.key), label: x.label })) })
}

/** one key, one thing to do with the toy; true when the key was one of them. Off the sandbox only the room's keys, with OFFICE_TOY_KEYS=1 */
function toyKey(k: string): boolean {
  if (!app.world && !roomKey(k, detail(app, ctl).actions.some((x) => x.key === k), TOY_KEYS)) return false
  switch (k) {
    case "E": open({ kind: "play" }); draw(); return true
    default: return false
  }
}

/** the status line for a scene asked for off the play card */
const scene = (started: boolean, r: { eventsHere(): boolean }, said: string): string =>
  started ? said : r.eventsHere() ? "a scene is running, or that event is switched off (the wackiness dial)" : "events need the wide room (kitty graphics)"

/** one toy off the play card, by its row id */
function playDo(id: string): void {
  const r = room(), under = app.mode.kind === "person" ? app.mode.name : null
  switch (id) {
    case "play.more": case "play.first": if (app.mode.kind === "play") { app.mode = { ...app.mode, page: id === "play.more" ? 2 : 1 }; app.sel = 0 }; break
    case "play.doorbell": r.play("doorbell"); app.status = "ding dong"; break
    case "play.gary": app.status = scene(r.event("gary"), r, "Gary's at the dumpster"); break
    case "play.zoo": app.status = scene(r.event("zoo"), r, "the zoo van is here"); break
    case "play.meteor": app.status = scene(r.event("meteor"), r, "incoming"); break
    case "play.power": app.status = scene(r.event("power"), r, "the lights go out"); break
    case "play.duck": app.status = scene(r.event("duck"), r, "a duck"); break
    case "play.planes": app.status = scene(r.event("planes"), r, "paper planes, and Argos is ready"); break
    case "play.pizza": app.status = scene(r.event("pizza"), r, "pizza in the kitchen"); break
    case "play.nap": app.status = scene(r.event("nap"), r, "lights down, heads down"); break
    case "play.chain": app.status = scene(r.chainReaction(), r, "Gary first; the rest follow"); break
    case "play.event": r.play("event"); app.status = r.eventNow() ? `event: ${r.eventNow()!.kind}` : r.eventsHere() ? (Object.values(resolveWhim(app.whim).events).some(Boolean) ? "something's up" : "events are switched off (the wackiness dial)") : "events need the wide room (kitty graphics)"; break
    case "play.drill": app.status = r.play("drill") ? "fire drill!" : "a scene is running — no drill until it ends"; break
    case "play.treat": r.catDo("come"); if (r instanceof WideRoom) r.dogDo("office"); app.status = "treat! they come running"; break
    case "play.night": if (!app.world) return; app.world.toggleNight(); for (const x of app.rooms.values()) x.setClock(app.world.now); app.status = app.world.now().getHours() === 23 ? "night falls" : "morning"; break
    case "play.weather": if (!app.world) return; app.world.nextWeather(); app.status = `weather: ${app.world.snapshot().weather!.desc.toLowerCase()}`; void refresh(); break
    case "play.pet": if (app.mode.kind === "pet" && app.mode.who === "dog" && r instanceof WideRoom) r.patDog(); else if (under) r.pat(under); else r.pet(); app.status = "pat pat"; break
    case "play.call": if (!app.world) return; app.world.callOver(under ?? app.world.snapshot().bench[1]!.name); app.status = `calling someone over to ${under ?? "the desk"}`; void refresh(); break
  }
}

function onKey(k: string) {
  app.keyLog = [...app.keyLog, k].slice(-KONAMI.length)
  if (isKonami(app.keyLog)) { app.keyLog = []; record(findSecret(app.trophies, "konami")); room().disco(); app.status = "↑↑↓↓←→←→BA — everybody dance"; changed(app); return draw() }
  if (k === ROOM_CTRL) return toRoom()
  if (app.picker) return pickerKey(k)
  if (app.input) return inputKey(k)
  if (app.confirm) {
    const c = app.confirm; app.confirm = null
    if (k === "y" || k === "enter") c.run()
    else { app.status = "cancelled"; if (app.reader) app.reader.status = app.status }
    return draw()
  }
  if (app.mode.kind === "look-editor") return editorKey(k)
  if (app.mode.kind === "hall" && (k === "tab" || k === "backtab")) { app.snapSel = false; app.sel = stepRow(app.sel, k === "tab" ? 1 : -1); return draw() }
  if (app.mode.kind === "store" && (k === "tab" || k === "backtab")) { app.snapSel = false; app.sel = stepStoreRow(app.sel, k === "tab" ? 1 : -1); return draw() }
  if (app.reader) {
    const r = app.reader.key(k, Math.max(1, (process.stdout.rows ?? 24) - 6))
    if (r === "leave") return closeReader()
    if (r === "pass") return threadActions(app, ctl, app.reader.tid, true).find((x) => x.key === k)?.run()
    if (r !== "done") void r.then(draw)
    return draw()
  }
  const box = cardBox(app)
  if (box?.focused) return boxKey(box, k)
  // a live thread's own ⏎ steps into the session; on any other thread card ⏎ is back into the box
  if (box && k === "enter" && !detail(app, ctl).actions.some((x) => x.key === "enter")) { box.focused = true; return draw() }
  if (toyKey(k)) return
  // the card's own actions first: a key there means what its actions pane says
  const name = k === " " ? "space" : k
  const own = detail(app, ctl).actions.find((x) => x.key === name)
  if (own) return own.run()
  const onActions = actionsFocused()
  switch (k) {
    case "q": case "ctrl-c": return quit()
    case "esc": back(); app.roomChanged = true; return draw()
    case "[": return stepWs(-1)
    case "]": return stepWs(1)
    case "tab": case "backtab": {
      const crew = crewOf(view(app))
      if (!crew.length) return
      const i = app.mode.kind === "person" ? crew.findIndex((c) => c.name === (app.mode as { name: string }).name) : -1
      return open({ kind: "person", name: crew[(i + (k === "tab" ? 1 : -1) + crew.length) % crew.length]!.name })
    }
    case "j": case "down":
      app.snapSel = false
      if (onActions) app.asel = Math.min(app.asel + 1, app.acts.length - 1); else app.sel = Math.min(app.sel + 1, app.rows.length - 1)
      return draw()
    case "k": case "up":
      app.snapSel = false
      if (onActions) app.asel = Math.max(app.asel - 1, 0); else app.sel = Math.max(app.sel - 1, 0)
      return draw()
    case "left": if (app.mode.kind === "column") return open({ kind: "column", col: (app.mode.col + COLS.length - 1) % COLS.length }); return
    case "shift-up": case "shift-down": case "shift-left": case "shift-right": {
      const dx = app.g.cw / app.g.k, dy = app.g.ch / app.g.k
      const [ddx, ddy] = k === "shift-left" ? [-dx, 0] : k === "shift-right" ? [dx, 0] : k === "shift-up" ? [0, -dy] : [0, dy]
      app.viewport = panViewport(app.viewport, ddx, ddy, app.g.floorW, app.g.floorH); app.follow = false; app.panned = true
      return draw()
    }
    case ".":
      app.viewport = centerViewport(app.viewport, OFF_W / 2, (BAND + OFF_DOOR) / 2, app.g.floorW, app.g.floorH); app.follow = true; app.panned = true
      return draw()
    case ",": {
      const need = app.needs[0]
      const seat = need ? app.all.roster.find((r) => r.thread_id === need.thread_id) : null
      const at = seat ? room().at(seat.agent) : null
      if (!at) return
      app.viewport = centerViewport(app.viewport, at.x, at.y, app.g.floorW, app.g.floorH); app.panned = true
      return draw()
    }
    case "pgdn": case "pgup": return page(k === "pgdn" ? 1 : -1)
    case "enter":
      if (app.mode.kind === "home" && app.lit !== null && !app.reader) return act({ kind: "thread", tid: app.lit })
      return onActions ? app.acts[app.asel]?.run() : app.rows[app.sel]?.open?.()
    case "/": case "ctrl-k": return void finder()
    case "?": return help()
    case "i": return inbox()
    case "R": if (updated()) void relaunch(); return
    case "'": return talk(null)
    case "n": return newThread()
    case "I": return newTicket()
    case "c": return open({ kind: "crew" })
    case "t": return open({ kind: "column", col: 0 })
    case "o": return open({ kind: "notes" })
    case "f": return open({ kind: "archive" })
    case "a": return open({ kind: "calendar" })
    case "w": return open({ kind: "tray" })
    case "!": return open({ kind: "triage" })
    case "H": return open({ kind: "health" })
    case "b": return open({ kind: "memory" })
    case "L": if (app.all.life?.[String(app.ws)]) open({ kind: "life" }); return
    case "B": if (flagOn(app.all, "build_mode")) open({ kind: "build" }); return
    case "U": return open({ kind: "entry" })
    case "O": return open({ kind: "boss" })
    case "S": return open({ kind: "settings" })
    case "p": room().pet(); changed(app); return draw()
  }
}

/** a page of the card's rows, by the selection when they open, else by the view */
function page(dir: 1 | -1, by = Math.max(1, app.pane.room - 2)) {
  app.snapSel = false
  if (actionsFocused()) app.scroll = Math.max(0, (Number.isFinite(app.scroll) ? app.scroll : app.pane.first) + dir * by)
  else app.sel = Math.max(0, Math.min(app.sel + dir * by, app.rows.length - 1))
  draw()
}

function onPaste(text: string) {
  if (app.picker) { app.picker.q.insert(text); return draw() }
  if (app.input) { app.input.ed.insert(text); return draw() }
  if (app.reader) { app.reader.paste(text); return draw() }
  const box = cardBox(app)
  if (box) { box.ed.insert(text); box.focused = true; return draw() }
}

/** the margin notes over a clipped frame: text ink after the clip so a pan can't push it off-screen, hits first so they win */
function addMargin(fr: Frame, vp: Viewport) {
  app.looks.see(app.notes, app.focused)
  const m = marginInk(app.notes, app.looks, app.lit, vp, app.g ? measureFor(app.g) : undefined)
  fr.ink.push(...m.ink)
  fr.hits.unshift(...m.hits)
}

function onMouse(m: Extract<Input, { t: "mouse" }>) {
  if (!app.frame || !app.g || app.reader) return
  const inRoom0 = m.row - 1 >= app.g.row && m.row - 1 < app.g.row + app.g.rows
  if (m.motion && m.button === 0) {
    if (inRoom0 && app.drag) {
      const dx = (app.drag.col - m.col) * (app.g.cw / app.g.k), dy = (app.drag.row - m.row) * (app.g.ch / app.g.k)
      app.viewport = panViewport(app.viewport, dx, dy, app.g.floorW, app.g.floorH); app.follow = false; app.panned = true
      app.drag = { col: m.col, row: m.row }
      return draw()
    }
    if (inRoom0) app.drag = { col: m.col, row: m.row }
    return
  }
  app.drag = null
  // the wheel over the pane scrolls it
  if (m.press && (m.button === 64 || m.button === 65) && m.row > app.pane.top) return page(m.button === 65 ? 1 : -1, 3)
  const clipped = clipFrame(app.frame, app.viewport)
  addMargin(clipped, app.viewport)
  const h = hitAt(clipped, app.g, m.col, m.row, app.viewport)
  if (m.motion) {
    const t = h?.tip ?? "", over = h?.note ?? null
    if (over !== app.lit) { app.lit = over; app.tip = t; app.roomChanged = true; return draw() }
    if (t !== app.tip) { app.tip = t; draw() }
    return
  }
  if (!m.press || m.button !== 0) return
  if (m.row === 1) return app.headHits.find((x) => m.col >= x.from && m.col <= x.to)?.go()
  const inRoom = inRoom0
  if (h) return act(h.act)
  // a click on bare floor clears the slate, as on the desktop
  if (inRoom) { back(true); app.roomChanged = true; return draw() }
  // the pane: a click on an action runs it, on a row opens it
  const i = m.row - app.pane.top - 1
  if (i < 0) return
  if (m.col > app.pane.leftW + 1) {
    const ai = app.pane.actAt[i], x = ai === undefined ? undefined : app.acts[ai]
    if (x) { app.asel = ai!; x.run() }
    return
  }
  const ri = app.pane.rowAt[i], r = ri === undefined ? undefined : app.rows[ri]
  if (r?.open) { app.sel = ri!; r.open() }
}

// ── zoomed into a terminal ─────────────────────────────────────────────────────────────────────
// The whole screen is one coworker's terminal: a bar on top, every key to the pane but Ctrl-],
// which goes to the room.
const ROOM_KEY = 0x1d // Ctrl-]
/** Ctrl-] as `tokenize` names it: a control character is ctrl- and its byte + 0x60 */
const ROOM_CTRL = "ctrl-}"

async function zoomInto(tid: number) {
  const target = await data.terminal(tid)
  if (!target) { app.status = `#${tid} has no live terminal`; if (app.reader) app.reader.status = app.status; return draw() }
  zoomOn(target, `#${tid} ${threadOf(app, tid)?.lead ?? target.window} · terminal`)
}
/**
 * lazygit in the thread's worktree, in a tmux session the office keeps (`-L tlon-office`, one per
 * thread), so it is where you left it next time; quitting lazygit closes the window and the zoom.
 */
// a drive names its own (scripts/office-drive.sh), so its panes and files never land in the operator's office
const OWN_TMUX = process.env.TLON_OFFICE_TMUX || "tlon-office"
const OWN_DIR = `${process.env.XDG_RUNTIME_DIR ?? "/tmp"}/${OWN_TMUX}`
async function zoomGit(tid: number) {
  if (!Bun.which("lazygit")) { app.status = "lazygit is not installed"; return draw() }
  const path = await data.worktree(tid)
  if (!path) { app.status = `#${tid} has no repo to show`; return draw() }
  const session = `git-${tid}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "lazygit", "-c", path, "lazygit")
  zoomOn({ socket: OWN_TMUX, session, window: "lazygit" }, `#${tid} ${threadOf(app, tid)?.lead ?? ""} · git`)
}
/** a workline's docs, picked from a list */
async function pickDoc(tid: number) {
  const names = await data.docs(tid)
  if (!names.length) { app.status = `#${tid} has no docs yet`; return draw() }
  find(`DOCS · #${tid}`, names.map((n) => ({ segs: [{ s: n, fg: ROLE.prose }], text: n, run: () => { app.picker = null; void readDoc(tid, n) } })))
}
/** a doc read in the office's own tmux: glow renders markdown, else bat, else less */
async function readDoc(tid: number, name: string) {
  const text = await data.doc(tid, name)
  if (text === null) { app.status = `#${tid}: no ${name}`; return draw() }
  pageThrough(`doc-${tid}-${name.replace(/\W/g, "_")}`, text, `#${tid} · ${name}`)
}
function pageThrough(session: string, text: string, label: string) {
  const dir = OWN_DIR, file = `${dir}/${session}`
  mkdirSync(dir, { recursive: true }); writeFileSync(file, text)
  const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  tmux("kill-session", "-t", `=${session}`)
  const show = `if command -v glow >/dev/null; then glow -p "$0"; elif command -v bat >/dev/null; then bat --paging=always --style=plain -l md "$0"; else less "$0"; fi`
  tmux("new-session", "-d", "-s", session, "-n", "doc", "sh", "-c", show, file)
  zoomOn({ socket: OWN_TMUX, session, window: "doc" }, label)
}
async function readPage(id: number) {
  if (app.ws === null) return
  const p = await data.dumpPage(app.ws, id)
  if (!p) { app.status = "that page can't be read: the server isn't answering"; return draw() }
  pageThrough(`page-${app.ws}-${id}`, p.body, `the dump · ${stamp(p.at)}`)
}
/** an earlier page made the dump again; the page it replaces is kept, so this is undone the same way */
async function restorePage(id: number) {
  if (app.ws === null) return
  const w = app.ws, p = await data.dumpPage(w, id)
  if (!p) { app.status = "that page can't be read: the server isn't answering"; return draw() }
  if (Bun.spawnSync(["tmux", "-L", OWN_TMUX, "has-session", "-t", `=dump-${w}`]).exitCode === 0) { app.status = "the dump is open in its editor: close it first, then put the page back"; return draw() }
  let file: string | null = null
  try { file = readFileSync(dumpFile(w), "utf8") } catch {}
  const now = await data.dump(w)
  if (!now) { app.status = "the dump can't be read: the server isn't answering"; return draw() }
  if (app.dumpSending.has(w) || (file?.trim() && file !== now.body)) { app.status = "the dump has a save still on its way: D to send it, then put the page back"; return draw() }
  await did(data.dumpPut(w, p.body).then((r) => {
    if (r.ok) { app.dumpSent.set(w, p.body); mkdirSync(dirname(dumpFile(w)), { recursive: true }); writeFileSync(dumpFile(w), p.body) }
    return r.line
  }))
  await loadCard(); draw()
}
// on disk, not the runtime tmpfs: words the server hasn't taken yet survive a logout or a reboot
const dumpFile = (w: number) => join(STATE_DIR, OWN_TMUX, `dump-${w}.md`)
function syncDump(w: number, quiet = false) {
  let text: string
  try { text = readFileSync(dumpFile(w), "utf8") } catch { return }
  if (text === app.dumpSent.get(w)) return
  if (app.dumpSending.has(w)) { app.dumpAgain.add(w); return }
  if (!text.trim()) { if (quiet) return; app.status = "the dump came back blank — not saved; the last page stands"; return draw() }
  // a quiet retry waits a minute after a refusal, so a server away or refusing is not hammered
  if (quiet && Date.now() - (app.dumpFailedAt.get(w) ?? 0) < 60_000) return
  app.dumpSending.add(w)
  const put = data.dumpPut(w, text).then((r) => {
    app.dumpSending.delete(w)
    if (r.ok) { app.dumpSent.set(w, text); app.dumpFailedAt.delete(w) } else app.dumpFailedAt.set(w, Date.now())
    if (app.dumpAgain.delete(w)) syncDump(w)
    return r
  })
  // quiet runs from inside a refresh, so it must not start another (`did` does)
  if (quiet) void put.then((r) => { if (r.ok) { app.status = r.line; draw() } })
  else void did(put.then((r) => r.line)).then(loadCard).then(draw)
}
async function openDump() {
  if (app.ws === null) return
  const w = app.ws, session = `dump-${w}`, file = dumpFile(w), tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  const open = tmux("has-session", "-t", `=${session}`).exitCode === 0
  // an editor an older office started writes to the runtime dir: its words are brought across, and kept coming while it is open
  const old = `${OWN_DIR}/dump-${w}.md`
  if (existsSync(old)) {
    mkdirSync(dirname(file), { recursive: true })
    const bring = () => { try { const t = readFileSync(old, "utf8"); if (t.trim()) writeFileSync(file, t) } catch {} }
    bring()
    if (open && !app.dumpOldWatched.has(w)) { app.dumpOldWatched.add(w); watchFile(old, { interval: 1000 }, bring) }
    else unlinkSync(old)
  }
  if (!open || !app.dumpSent.has(w)) {
    const page = await data.dump(w)
    if (!page) { app.status = "the dump can't be read: the server isn't answering"; return draw() }
    if (!app.dumpSending.has(w)) app.dumpSent.set(w, page.body)
  }
  if (!app.dumpWatched.has(w)) { app.dumpWatched.add(w); watchFile(file, { interval: 1000 }, () => syncDump(w)) }
  if (!open) {
    let unsent: string | null = null
    try { unsent = readFileSync(file, "utf8") } catch {}
    if (unsent?.trim() && unsent !== app.dumpSent.get(w)) { app.status = "sending what you wrote while the server was away"; syncDump(w) }
    else { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, app.dumpSent.get(w)!) }
    tmux("new-session", "-d", "-s", session, "-n", "dump", ...EDITOR_ENV(), "sh", "-c", EDIT_SH, file)
  }
  zoomOn({ socket: OWN_TMUX, session, window: "dump" }, "the dump", () => syncDump(w))
}
// VISUAL/EDITOR is a shell command, as git reads it: flags work, and a path with spaces is quoted inside it
const EDIT_SH = `e="\${VISUAL:-\${EDITOR:-}}"; [ -n "$e" ] || e="$(command -v nvim || command -v vi)"; [ -n "$e" ] || { echo "no editor: set VISUAL or EDITOR"; read _; exit 1; }; eval "exec $e \\"\\$0\\""`
// a tmux server already up keeps its own env, so the editor this TUI was started with is handed over
const EDITOR_ENV = () => ["VISUAL", "EDITOR"].flatMap((k) => (process.env[k] ? ["-e", `${k}=${process.env[k]}`] : []))
/** a seat's soul in the operator's own editor, zoomed like the dump; the file starts blank when absent and is never overwritten */
function openSoul(name: string) {
  const file = join(SOULS, `${name}.md`), session = `soul-${name}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  try { mkdirSync(SOULS, { recursive: true }); writeFileSync(file, BLANK_SOUL, { flag: "wx" }) } catch { /* theirs already: never overwritten */ }
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "soul", ...EDITOR_ENV(), "sh", "-c", EDIT_SH, file)
  zoomOn({ socket: OWN_TMUX, session, window: "soul" }, "the soul", () => { app.soulsSeen = "" })
}
/** a game in the office's own tmux, one session each, so a game you leave is where you left it */
function play(g: (typeof GAMES)[number]) {
  const session = `arcade-${g.cmd}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "game", g.cmd)
  zoomOn({ socket: OWN_TMUX, session, window: "game" }, `arcade · ${g.name}`)
}
function zoomOn(target: Target, label: string, after?: () => void) {
  const colsN = cols(), rowsN = Math.max(2, (process.stdout.rows ?? 24) - 1)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[?1003l${ESC}[?1006l${ESC}[?2004l${ESC}[2J`)
  app.zoom = { label, after, view: new TerminalView(target, colsN, rowsN, () => drawZoom(), () => leaveZoom()) }
  drawZoom()
}
function drawZoom() {
  if (!app.zoom) return
  const colsN = cols(), vt = app.zoom.view.vt
  // no autowrap while drawing: a row the VT and this terminal measure differently can't wrap and scroll the bar away
  let o = `${ESC}[?2026h${ESC}[?7l${ESC}[?25l${ESC}[1;1H` + line([{ s: " ROOM ", fg: ROLE.ground, bg: ROLE.attention }, key(" ctrl+] room "), { s: app.zoom.label, fg: ROLE.body, bold: true }], colsN)
  vtRows(vt).forEach((r, i) => { o += `${ESC}[${i + 2};1H${r}` })
  const b = vt.buffer.active
  o += `${ESC}[?7h${ESC}[${b.cursorY + 2};${b.cursorX + 1}H${ESC}[?25h${ESC}[?2026l`
  out(o)
}
function leaveZoom(toTheRoom = false): void {
  if (!app.zoom) return
  const z = app.zoom
  app.zoom = null
  z.view.close()
  out(`${ESC}[0m${ESC}[?25l${ESC}[?1003h${ESC}[?1006h${ESC}[?2004h`)
  z.after?.()
  if (toTheRoom) return toRoom()
  if (app.reader) { out(`${ESC}[2J`); return draw() }
  layoutScreen(); draw()
}
/** raw keys while zoomed: Ctrl-] goes to the room, the rest goes to the pane as it came */
function zoomInput(b: Uint8Array) {
  const at = b.indexOf(ROOM_KEY)
  if (at < 0) return app.zoom?.view.send(b)
  app.zoom?.view.send(b.subarray(0, at))
  leaveZoom(true)
}
/** Ctrl-] from anywhere: the room with nothing open over it */
function toRoom(): void {
  if (app.zoom) return leaveZoom(true)
  if (app.input && !app.input.ed.empty) app.banked.set(app.input.label, app.input.ed.text)
  bankReader()
  app.reader = null; app.input = null; back(true); app.roomChanged = true
  out(`${ESC}[?25l`); layoutScreen(); draw()
}

function quit() { app.zoom?.view.close(); leave(); process.exit(0) }

// ── startup ────────────────────────────────────────────────────────────────────────────────────
const ctl: Boot = {
  open, back, act, ask, ask2, did, draw, refresh, loadCard, find, room, back1, resort, hire, talk, reply, newThread, newTicket, newNote,
  finder, inbox, quit, goThread, goWs, openReader, closeReader, openConversation, openBabel, openDump, openSoul, readPage, restorePage,
  zoomInto, zoomGit, pickDoc, play, playDo, setWhim, followPets: () => followPets(app),
  loadThread, zoomInput, onKey, onPaste, stampLooked, onMouse, layoutScreen, drawZoom, watchTrophies, leaveZoom, openThread, paint,
  detail: () => detail(app, ctl),
}

void boot(app, ctl)
