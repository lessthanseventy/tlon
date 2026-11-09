// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { arrivals } from "../kit/door"
import { babelPage, clockFace, hasFound } from "../kit/eggs"
import { bump as bumpTally, findSecret, newlyWon, night, serialize as serializeTally, won as wonTrophies, type Tally } from "../kit/trophies"
import { existsSync, mkdirSync, readFileSync, unlinkSync, watchFile, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { reactLine, seatLine } from "../kit/seat-voices"
import type { EventKind } from "../kit/events"
import { save as saveWhim } from "../kit/whimsy-file"
import { resolve as resolveWhim, type State as WhimState } from "../kit/whimsy"
import { tickFromTriage, tickSlap } from "../kit/scharlach"
import { busiest, crewOf, needsYou, type Act } from "../kit/crew"
import { resolvePets } from "../kit/pets"
import { lastLanding } from "../kit/tv"
import { baseLook, overrideFor } from "../kit/looks"
import { ROLE } from "../kit/palette"
import { BLANK_SOUL, candidateOf } from "../kit/hall"
import { shirtOf } from "../kit/sprites"
import { operatorOf, type Agents } from "../kit/types"
import { RailRoom } from "../rooms/rail"
import { WideRoom } from "../rooms/wide"
import { say, lobbyOf, replies, conversation, speech } from "./talk"
import * as data from "./data"
import { bind } from "./keys"
import { Editor } from "./editor"
import { ticketPicks } from "./finder"
import { loadPets } from "./pets"
import { Reader, type ReaderDeps } from "./reader"
import { ESC, leave, line, out } from "./term"
import { rows as vtRows, TerminalView, type Target } from "./terminal"
import { oneInFlight } from "./flight"
import { earmarkOf, earmarksOut, freshPosts, handoffFrom } from "../kit/plane"
import { State, STATE_DIR, STATE, TRAY, SAID, EARS, LOOKED, SOULS, OFFICE, writeState, TROPHY_FILE, type Mode, type Cycle, type Prompt, type Pick, type Action } from "./state"
import { detail } from "./cards/index"
import { cardBox, changed, hallCtx, threadOf, view, wsName } from "./select"
import { DETAIL, cardKey, cols, key, paneW, stamp, tidSeg } from "./ui"
import { NEED_KIND } from "./cards/needs"
import { newSchedule } from "./cards/schedule"
import { GAMES } from "./cards/home"
import { boot, followPets } from "./boot"
import type { Screen } from "./ctl"
import { draw, layoutScreen, paint, scene } from "./draw"
import { onKey, onMouse, onPaste } from "./input"

const app = new State()

if (app.world) data.useFake(app.world)

/** step an ordering, keeping the cursor on the row (by its `ref`) it was on */
function resort(step: () => void) {
  const was = app.rows[app.sel]?.ref
  step()
  const at = was === undefined ? -1 : detail(app, ctl).rows.findIndex((r) => r.ref === was)
  if (at >= 0) app.sel = at
  draw(app, ctl)
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

const room = () => { const k = app.ws ?? 0; let r = app.rooms.get(k); if (!r) { app.rooms.set(k, (r = app.wide ? new WideRoom(app.wide) : new RailRoom())); r.setWhimsy(resolveWhim(app.whim)); if (app.petsNow) r.setPets(app.petsNow); if (r instanceof WideRoom) { r.setHome(app.homeNow); r.setTrophies(wonTrophies(app.trophies).length) } r.reactLine = reactFor; r.onSlap = () => { app.ledger = tickSlap(app.ledger) } } return r }
/** the dial moved: remember it and hand every room the resolved dials */
function setWhim(s: WhimState) {
  app.whim = s
  saveWhim(OFFICE, s)
  for (const r of app.rooms.values()) r.setWhimsy(resolveWhim(s))
  changed(app)
}

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
  draw(app, ctl)
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
  draw(app, ctl)
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
  void Promise.all([tid !== null ? loadThread(tid) : null, loadCard()]).then(() => draw(app, ctl))
  draw(app, ctl)
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
    case "tv": { const r = room(); if (r instanceof WideRoom) { r.channel(); changed(app); draw(app, ctl) } return }
    case "arcade": return open({ kind: "arcade" })
    case "ideas": return open({ kind: "ideas" })
    case "weather": app.status = app.all.weather ? `outside: ${app.all.weather.desc.toLowerCase()}${app.all.weather.temp_c === null ? "" : `, ${app.all.weather.temp_c}°C`}` : "no word on the weather"; return draw(app, ctl)
  }
}

// ── writing: the inputs ─────────────────────────────────────────────────────────────────────────
function ask(label: string, submit: Prompt["submit"], opts: { multiline?: boolean; text?: string; cycles?: Cycle[] } = {}) {
  const held = app.banked.get(label)
  app.banked.delete(label)
  app.input = { label, ed: new Editor(held ?? opts.text ?? "", !!opts.multiline), submit, cycles: opts.cycles, focus: 0 }
  draw(app, ctl)
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
  if (box?.tid === tid) { box.focused = true; return draw(app, ctl) }
  openReader(tid)
}
function hire() {
  if (app.ws === null) return
  const w = app.ws, kinds = app.all.archetypes.map((x) => ({ label: `${x.name}${x.meta ? " (manager)" : x.read_only ? " (read-only)" : ""}`, value: x.name }))
  if (!kinds.length) { app.status = "no archetypes to hire from"; return draw(app, ctl) }
  ask("hire — their name", (s, [arch]) => { if (s.trim()) did(data.hire(w, s.trim(), arch as string)) }, { cycles: [{ name: "as", values: kinds, i: Math.max(0, kinds.findIndex((k) => k.value === "builder")) }] })
}

// ── the finder ─────────────────────────────────────────────────────────────────────────────────
function find(title: string, items: Pick[]) { app.picker = { title, q: new Editor("", false), items, sel: 0 }; draw(app, ctl) }
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
    draw(app, ctl)
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
  app.reader = new Reader(tid, { load: (before) => (before ? data.page(tid, before) : data.thread(tid)), send: (body) => data.post(tid, body), operator: operatorOf(app.all), redraw: () => draw(app, ctl), dogeared: (m) => app.earmarked.has(earmarkOf(tid, m.at, m.author)), ...extra }, focus, app.cardReply?.tid === tid ? app.cardReply.ed.text : "")
  if (app.cardReply?.tid === tid) app.cardReply = null
  const v = app.threads.get(tid)
  if (v) app.reader.take(v)
  void app.reader.reload().then(() => draw(app, ctl))
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
  draw(app, ctl)
}
/** the conversation with `name`: the lobby filtered to them and the operator's words to them; a reply goes to them */
function openConversation(name: string) {
  const lobby = lobbyOf(view(app).threads, app.ws)
  if (lobby === null) { app.status = "no front desk in this workspace"; return draw(app, ctl) }
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
  layoutScreen(app, ctl); draw(app, ctl)
}
const ask2 = (label: string, run: () => void) => { app.confirm = { label, run }; draw(app, ctl) }

// ── the detail pane ────────────────────────────────────────────────────────────────────────────

const back1: Action = { ...bind("back.esc"), run: () => { back(); app.roomChanged = true; draw(app, ctl) } }

// ── drawing ────────────────────────────────────────────────────────────────────────────────────

// ── input ──────────────────────────────────────────────────────────────────────────────────────

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

// ── zoomed into a terminal ─────────────────────────────────────────────────────────────────────
// The whole screen is one coworker's terminal: a bar on top, every key to the pane but Ctrl-],
// which goes to the room.
const ROOM_KEY = 0x1d // Ctrl-]

async function zoomInto(tid: number) {
  const target = await data.terminal(tid)
  if (!target) { app.status = `#${tid} has no live terminal`; if (app.reader) app.reader.status = app.status; return draw(app, ctl) }
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
  if (!Bun.which("lazygit")) { app.status = "lazygit is not installed"; return draw(app, ctl) }
  const path = await data.worktree(tid)
  if (!path) { app.status = `#${tid} has no repo to show`; return draw(app, ctl) }
  const session = `git-${tid}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "lazygit", "-c", path, "lazygit")
  zoomOn({ socket: OWN_TMUX, session, window: "lazygit" }, `#${tid} ${threadOf(app, tid)?.lead ?? ""} · git`)
}
/** a workline's docs, picked from a list */
async function pickDoc(tid: number) {
  const names = await data.docs(tid)
  if (!names.length) { app.status = `#${tid} has no docs yet`; return draw(app, ctl) }
  find(`DOCS · #${tid}`, names.map((n) => ({ segs: [{ s: n, fg: ROLE.prose }], text: n, run: () => { app.picker = null; void readDoc(tid, n) } })))
}
/** a doc read in the office's own tmux: glow renders markdown, else bat, else less */
async function readDoc(tid: number, name: string) {
  const text = await data.doc(tid, name)
  if (text === null) { app.status = `#${tid}: no ${name}`; return draw(app, ctl) }
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
  if (!p) { app.status = "that page can't be read: the server isn't answering"; return draw(app, ctl) }
  pageThrough(`page-${app.ws}-${id}`, p.body, `the dump · ${stamp(p.at)}`)
}
/** an earlier page made the dump again; the page it replaces is kept, so this is undone the same way */
async function restorePage(id: number) {
  if (app.ws === null) return
  const w = app.ws, p = await data.dumpPage(w, id)
  if (!p) { app.status = "that page can't be read: the server isn't answering"; return draw(app, ctl) }
  if (Bun.spawnSync(["tmux", "-L", OWN_TMUX, "has-session", "-t", `=dump-${w}`]).exitCode === 0) { app.status = "the dump is open in its editor: close it first, then put the page back"; return draw(app, ctl) }
  let file: string | null = null
  try { file = readFileSync(dumpFile(w), "utf8") } catch {}
  const now = await data.dump(w)
  if (!now) { app.status = "the dump can't be read: the server isn't answering"; return draw(app, ctl) }
  if (app.dumpSending.has(w) || (file?.trim() && file !== now.body)) { app.status = "the dump has a save still on its way: D to send it, then put the page back"; return draw(app, ctl) }
  await did(data.dumpPut(w, p.body).then((r) => {
    if (r.ok) { app.dumpSent.set(w, p.body); mkdirSync(dirname(dumpFile(w)), { recursive: true }); writeFileSync(dumpFile(w), p.body) }
    return r.line
  }))
  await loadCard(); draw(app, ctl)
}
// on disk, not the runtime tmpfs: words the server hasn't taken yet survive a logout or a reboot
const dumpFile = (w: number) => join(STATE_DIR, OWN_TMUX, `dump-${w}.md`)
function syncDump(w: number, quiet = false) {
  let text: string
  try { text = readFileSync(dumpFile(w), "utf8") } catch { return }
  if (text === app.dumpSent.get(w)) return
  if (app.dumpSending.has(w)) { app.dumpAgain.add(w); return }
  if (!text.trim()) { if (quiet) return; app.status = "the dump came back blank — not saved; the last page stands"; return draw(app, ctl) }
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
  if (quiet) void put.then((r) => { if (r.ok) { app.status = r.line; draw(app, ctl) } })
  else void did(put.then((r) => r.line)).then(loadCard).then(() => draw(app, ctl))
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
    if (!page) { app.status = "the dump can't be read: the server isn't answering"; return draw(app, ctl) }
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
  if (app.reader) { out(`${ESC}[2J`); return draw(app, ctl) }
  layoutScreen(app, ctl); draw(app, ctl)
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
  out(`${ESC}[?25l`); layoutScreen(app, ctl); draw(app, ctl)
}

function quit() { app.zoom?.view.close(); leave(); process.exit(0) }

// ── startup ────────────────────────────────────────────────────────────────────────────────────
const ctl: Screen = {
  open, back, act, ask, ask2, did, refresh, loadCard, find, room, back1, resort, hire, talk, reply, newThread, newTicket, newNote,
  finder, inbox, quit, goThread, goWs, openReader, closeReader, openConversation, openBabel, openDump, openSoul, readPage, restorePage,
  zoomInto, zoomGit, pickDoc, play, playDo, setWhim, followPets: () => followPets(app),
  loadThread, zoomInput, stampLooked, drawZoom, watchTrophies, leaveZoom, openThread, record, toRoom,
  draw: () => draw(app, ctl), layoutScreen: () => layoutScreen(app, ctl), paint: (roomOnly) => paint(app, ctl, roomOnly),
  onKey: (k) => onKey(app, ctl, k), onPaste: (text) => onPaste(app, ctl, text), onMouse: (m) => onMouse(app, ctl, m),
  detail: () => detail(app, ctl),
}

void boot(app, ctl)
