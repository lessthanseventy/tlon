// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { babelPage, hasFound } from "../kit/eggs"
import { findSecret, won as wonTrophies } from "../kit/trophies"
import { save as saveWhim } from "../kit/whimsy-file"
import { resolve as resolveWhim, type State as WhimState } from "../kit/whimsy"
import { tickSlap } from "../kit/scharlach"
import { busiest, crewOf, needsYou, type Act } from "../kit/crew"
import { resolvePets } from "../kit/pets"
import { baseLook, overrideFor } from "../kit/looks"
import { ROLE } from "../kit/palette"
import { candidateOf } from "../kit/hall"
import { shirtOf } from "../kit/sprites"
import { operatorOf } from "../kit/types"
import { RailRoom } from "../rooms/rail"
import { WideRoom } from "../rooms/wide"
import { say, lobbyOf, conversation, speech } from "./talk"
import * as data from "./data"
import { bind } from "./keys"
import { Editor } from "./editor"
import { ticketPicks } from "./finder"
import { loadPets } from "./pets"
import { Reader, type ReaderDeps } from "./reader"
import { ESC, out } from "./term"
import { oneInFlight } from "./flight"
import { earmarkOf } from "../kit/plane"
import { State, STATE, OFFICE, writeState, type Mode, type Cycle, type Prompt, type Pick, type Action } from "./state"
import { detail } from "./cards/index"
import { cardBox, changed, hallCtx, threadOf, view, wsName } from "./select"
import { DETAIL, cardKey, paneW, tidSeg } from "./ui"
import { newSchedule } from "./cards/schedule"
import { boot, followPets } from "./boot"
import type { Screen } from "./ctl"
import { draw, layoutScreen, paint, scene } from "./draw"
import { onKey, onMouse, onPaste } from "./input"
import { drawZoom, leaveZoom, openDump, openSoul, pickDoc, play, quit, readPage, restorePage, toRoom, zoomGit, zoomInput, zoomInto } from "./zoom"
import { loadCard, loadThread, reactFor, record, refreshOnce, stampLooked, watchTrophies } from "./refresh"

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

const room = () => { const k = app.ws ?? 0; let r = app.rooms.get(k); if (!r) { app.rooms.set(k, (r = app.wide ? new WideRoom(app.wide) : new RailRoom())); r.setWhimsy(resolveWhim(app.whim)); if (app.petsNow) r.setPets(app.petsNow); if (r instanceof WideRoom) { r.setHome(app.homeNow); r.setTrophies(wonTrophies(app.trophies).length) } r.reactLine = (who, kind) => reactFor(app, who, kind); r.onSlap = () => { app.ledger = tickSlap(app.ledger) } } return r }
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
const refresh = oneInFlight(() => refreshOnce(app, ctl))
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
  void Promise.all([tid !== null ? loadThread(app, tid) : null, loadCard(app)]).then(() => draw(app, ctl))
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
    case "terminal": return void zoomInto(app, ctl, x.tid)
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
  if (hasFound(page)) record(app, findSecret(app.trophies, "babel"))
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

// ── startup ────────────────────────────────────────────────────────────────────────────────────
const ctl: Screen = {
  open, back, act, ask, ask2, did, refresh, find, room, back1, resort, hire, talk, reply, newThread, newTicket, newNote,
  finder, inbox, goThread, goWs, openReader, closeReader, openConversation, openBabel, playDo, setWhim, bankReader, followPets: () => followPets(app),
  quit: () => quit(app), openDump: () => openDump(app, ctl), openSoul: (name) => openSoul(app, ctl, name), readPage: (id) => readPage(app, ctl, id), restorePage: (id) => restorePage(app, ctl, id),
  zoomInto: (tid) => zoomInto(app, ctl, tid), zoomGit: (tid) => zoomGit(app, ctl, tid), pickDoc: (tid) => pickDoc(app, ctl, tid), play: (g) => play(app, ctl, g),
  openThread, settleWorkspace,
  loadCard: () => loadCard(app), loadThread: (tid) => loadThread(app, tid), stampLooked: () => stampLooked(app), watchTrophies: () => watchTrophies(app), record: (next) => record(app, next),
  zoomInput: (b) => zoomInput(app, ctl, b), drawZoom: () => drawZoom(app), leaveZoom: (toTheRoom) => leaveZoom(app, ctl, toTheRoom), toRoom: () => toRoom(app, ctl),
  draw: () => draw(app, ctl), layoutScreen: () => layoutScreen(app, ctl), paint: (roomOnly) => paint(app, ctl, roomOnly),
  onKey: (k) => onKey(app, ctl, k), onPaste: (text) => onPaste(app, ctl, text), onMouse: (m) => onMouse(app, ctl, m),
  detail: () => detail(app, ctl),
}

void boot(app, ctl)
