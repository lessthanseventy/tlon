// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { random } from "../kit/rng"
import { arrivals } from "../kit/door"
import { babelPage, clockFace, hasFound, isKonami, KONAMI } from "../kit/eggs"
import { bump as bumpTally, findSecret, newlyWon, night, rows as trophyRows, serialize as serializeTally, won as wonTrophies, type Tally } from "../kit/trophies"
import { existsSync, mkdirSync, readFileSync, realpathSync, statSync, unlinkSync, watchFile, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { FLOOR, marginInk } from "../kit/margin"
import { reactLine, seatLine } from "../kit/seat-voices"
import type { EventKind } from "../kit/events"
import { save as saveWhim } from "../kit/whimsy-file"
import { resolve as resolveWhim, type State as WhimState } from "../kit/whimsy"
import { resetToPreset, whimsyRows, whimsyTitle } from "./whimsy-card"
import { ledgerLines, MUG, NAMEPLATE, SHERIFF, tickFromTriage, tickSlap } from "../kit/scharlach"
import { boardColumns, busiest, cardState, COLS, crewOf, groupRows, needsYou, openTotal, treeRows, BOARD_LEGEND, STATE_GLYPH, statusGlyph, statusTone, statusWord, viewOf, type Act, type SeatStatus, type BoardCtx, type CardState } from "../kit/crew"
import { entryOf } from "../kit/entry"
import { queueItems, type QueueItem } from "../kit/rack"
import { cycleAxis, dots, previewOf, resolvePets, SLOT_SPECIES, slotOf, SPECIES_BLURB, TEMPERAMENTS, type CatSpecies } from "../kit/pets"
import { AXES } from "../kit/temperament"
import { CELL, OFFICE_ROWS, defaultHome, drop, move, pickUp, place, remove, rotate, startBuild, undo, type Build } from "../kit/home"
import { renderHome } from "../kit/homeart"
import { mailbox } from "../kit/mailbox"
import { clipLabel, inboxSections, phoneBar, ringFrame } from "../kit/surfaces"
import { corkLabel, soulFor, useSouls } from "../kit/souls"
import { personCard } from "./person-card"
import { lastLanding } from "../kit/tv"
import { paced } from "./pace"
import { watchDirs } from "./watch"
import { loadSouls, soulsSignature } from "./souls"
import { baseLook, OPERATOR as MY_LOOK, overrideFor, trimCustom, useLookOverrides, type LookOverride } from "../kit/looks"
import { ROLE, useRoles, type Role } from "../kit/palette"
import { bedScene, lifeHeader, lifeRows, streakFrames } from "../kit/life"
import { usageHeader } from "../kit/usage"
import { dialsOf, nextDial, nextPart, PARTS, SLOTS } from "../kit/parts"
import { BLANK_SOUL, bringBack, candidateOf, dropPile, drawSoul, editField, hallSignature, loadHall, maybe, pass, saveHall, seatedNames, setLook, takenNames, toggleLock, type Hall, type Vocab } from "../kit/hall"
import { hallRows, lookHint, stepRow, type RowEdit } from "./hall"
import { castSignature, loadCast, saveCast, setTrait, type Cast } from "../kit/cast"
import { CAST_FIELDS, castRows, nextTrait, rerollTrait } from "./cast"
import { adopt, back as storeBack, candidateOf as storeCandidate, loadStore, pass as storePass, rename, saveStore, shelve, storeNamesTaken, toggleLock as storeToggle, type Store } from "../kit/store"
import { adoptAsk, stepStoreRow, storeRows } from "./store"
import { ACCESSORY, BODIES, HAIR_STYLES, HAIR_ROLES, lookOf, rollLook, OUTFIT, paints, shirtOf, SKIN_ROLES, type Accessory, type Look, type Outfit } from "../kit/sprites"
import { NOW_PLAYING_FORMAT, parseNowPlaying, type NowPlaying } from "../kit/stereo"
import { flagOn, operatorOf, type Agents, type CorkNote, type Coworker, type Thread } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"
import { BAND, OFF_DOOR, OFF_W, WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import { say, handToUqbar, lobbyOf, replies, conversation, speech } from "./talk"
import { studyOf } from "../kit/uqbar"
import * as data from "./data"
import { adder, bind, everywhere, hints, LEGEND_CHARS, type KeyId } from "./keys"
import { PLAY, PLAY_ROWS, ROOM_PLAY, WORLD_ROWS, roomKey } from "./sandbox"
import { Editor, wrap } from "./editor"
import { rank } from "./fuzzy"
import { ticketPicks } from "./finder"
import { applyBuild, loadFloor } from "./home"
import { loadPets, PETS_PATH, savePets } from "./pets"
import { geometry, hitAt, kittyImage, measureFor, textLayer } from "./paint"
import { READER_KEYS, Reader, type ReaderDeps } from "./reader"
import { timelineRows } from "./timeline"
import { footLines, follow as followSel, offset, type Hint, type Window } from "./pane"
import { badge, cells, enter, ESC, leave, line, mute, out, query, tokenize, type Input, type Seg } from "./term"
import { execSelf, selfArgv } from "./exec"
import { rows as vtRows, TerminalView, type Target } from "./terminal"
import { centerViewport, clipFrame, panViewport, type Viewport } from "./viewport"
import { parseWhen, showWhen } from "./when"
import { downHeader } from "./down"
import { oneInFlight } from "./flight"
import { earmarkOf, earmarksOut, freshPosts, handoffFrom } from "../kit/plane"
import { arrange, CREW_SORTS, next } from "./order"
import { State, STATE_DIR, STATE, TRAY, SAID, EARS, LOOKED, PALETTE, TOY_KEYS, LOOKS, SOULS, HALL, CAST, STORE, PLAY_SEEN, OFFICE, readState, writeState, TROPHY_FILE, CREW_GROUP_MODES, COL_SORTS, TRAY_SORTS, type Mode, type Row, type Cycle, type Prompt, type Pick, type Action } from "./state"

const app = new State()

const DETAIL = 14 // the detail pane's rows, title included: fixed, so nothing below the room moves

/** read-merge-write one agent's entry into looks.json, same shape as cli.ts's importer */
function saveLook(name: string, draft: LookOverride) {
  let all: Record<string, LookOverride> = {}
  try { all = JSON.parse(readFileSync(LOOKS, "utf8")) } catch { /* no file yet */ }
  all[name] = draft
  writeState(LOOKS, JSON.stringify(all, null, 2))
  app.looksSeen = "" // our own write: make the next poll re-read it instead of treating it as already seen
}

if (app.world) data.useFake(app.world)

const cardKey = (m: Mode) => JSON.stringify({ ...m, from: undefined })
const waiting = (what: string): Seg => { const why = app.readWhys.get(cardKey(app.mode)); return dim(why ? `couldn't read: ${why}` : what) }
/** the workspace's crews by name, as its seats are on them; `all` is every crew, no crew of its own */
const crewsOf = (w: number | null) => [...new Set((app.all.shifts ?? []).filter((x) => x.workspace_id === w && x.crew !== "all").map((x) => x.crew))].sort()
const tabLabel = (t: string) => (t === "all" ? "everyone" : t)
/** step an ordering, keeping the cursor on the row (by its `ref`) it was on */
function resort(step: () => void) {
  const was = app.rows[app.sel]?.ref
  step()
  const at = was === undefined ? -1 : detail().rows.findIndex((r) => r.ref === was)
  if (at >= 0) app.sel = at
  draw()
}
const GRADES = ["junior", "senior", "greybeard"], SPECIALTIES = ["office", "server"]
const hallVocab = (): Vocab => {
  const names = app.all.archetypes.filter((a) => !a.meta).map((a) => a.name)
  return { archetypes: names.length ? names : ["builder"], grades: GRADES, specialties: SPECIALTIES }
}
const hallCtx = () => ({ taken: takenNames(app.hall, seatedNames(app.all), hallVocab()), vocab: hallVocab() })
function hallSet(h: Hall) { app.hall = h; saveHall(HALL, h); app.hallSeen = hallSignature(HALL) }
/** a hand edit of hall.json shows up on the next poll; true when it did */
function followHall(): boolean {
  const seen = hallSignature(HALL)
  if (seen === app.hallSeen) return false
  app.hallSeen = seen; app.hall = loadHall(HALL)
  return true
}
function castSet(c: Cast) { app.cast = c; saveCast(CAST, c); app.castSeen = castSignature(CAST) }

function followCast(): boolean {
  const seen = castSignature(CAST)
  if (seen === app.castSeen) return false
  app.castSeen = seen; app.cast = loadCast(CAST)
  return true
}
/** `e` on the lit row: cycle a vocab field in place, ask for a name, the pitch or the soul, open the look card on a slot */
function hallEdit(what: RowEdit) {
  const ctx = hallCtx(), c = candidateOf(app.hall, ctx)
  const apply = (r: Hall | { error: string }) => { if ("error" in r) app.status = r.error; else hallSet(r); draw() }
  if ((SLOTS as readonly string[]).includes(what)) return open({ kind: "look", name: c.name, hall: true })
  if (what === "archetype" || what === "grade" || what === "specialty") {
    const opts = ctx.vocab[({ archetype: "archetypes", grade: "grades", specialty: "specialties" } as const)[what]]
    return apply(editField(app.hall, ctx, what, opts[(opts.indexOf(c[what]) + 1) % opts.length]!))
  }
  const f = what as "name" | "pitch" | "soul"
  // a name being edited is not taken by itself
  const own = { ...ctx, taken: ctx.taken.filter((n) => n !== c.name) }
  ask(f === "soul" ? `soul for ${c.name}` : `${f} for ${c.name}`, (s) => apply(editField(app.hall, own, f, s)), { text: c[f], multiline: f === "soul" })
}
async function hallDraw() {
  if (app.ws === null) return
  const c = candidateOf(app.hall, hallCtx())
  app.status = `drawing ${c.name}…`; draw()
  const r = await data.draftSoul(app.ws, c)
  if ("error" in r) app.status = r.error
  else if (candidateOf(app.hall, hallCtx()).name !== c.name) return draw()
  else { hallSet(drawSoul(app.hall, r)); app.status = `drew ${c.name}'s soul (${r.source}) — e to edit` }
  draw()
}
async function hallHire() {
  const ctx = hallCtx(), c = candidateOf(app.hall, ctx)
  if (ctx.taken.includes(c.name)) { app.status = `${c.name} is already on the bench — pass, or drop it`; return draw() }
  if (app.world) app.world.hire(c)
  else {
    if (app.ws === null) return
    const said = await data.hire(app.ws, c.name, c.archetype)
    // data.hire's own success line; anything else is the refusal, and nothing is kept
    if (!said.startsWith("hired ")) { app.status = said; return draw() }
  }
  saveLook(c.name, c.look)
  try { mkdirSync(SOULS, { recursive: true }); writeFileSync(join(SOULS, `${c.name}.md`), c.soul, { flag: "wx" }) } catch { /* theirs already: never overwritten */ }
  app.soulsSeen = ""
  hallSet(pass(app.hall, { ...ctx, taken: [...ctx.taken, c.name] }))
  app.status = `hired ${c.name}`
  void refresh()
  draw()
}
const storeTaken = () => storeNamesTaken(app.all.bench.map((b) => b.name), app.petsNow ?? resolvePets(loadPets()), app.store.species)
function storeSet(s: Store) { app.store = s; saveStore(STORE, s); app.storeSeen = hallSignature(STORE) }
/** a hand edit of store.json shows up on the next poll; true when it did */
function followStore(): boolean {
  const seen = hallSignature(STORE)
  if (seen === app.storeSeen) return false
  app.storeSeen = seen; app.store = loadStore(STORE)
  return true
}
/** ⏎: adopt the shown candidate into its slot; the occupant leaves by the door, once the operator says y */
function storeAdopt() {
  const taken = storeTaken(), c = storeCandidate(app.store, taken), slot = slotOf(c.species)
  const file = slot ? adopt(c, slot) : null
  if (!slot || !file) { app.status = `${c.name} can't be adopted here`; return draw() }
  const old = (app.petsNow ?? resolvePets(loadPets()))[slot].name
  ask2(adoptAsk(old, c.name), () => {
    savePets(file)
    app.petsSeen = ""; followPets(); app.roomChanged = true
    storeSet(storePass(app.store, [...taken, c.name]))
    app.status = `adopted ${c.name}`
    draw()
  })
}
const blankBuf = () => Array.from({ length: 22 }, () => ".".repeat(12))
/** a thread with an open prompt opens with its box unfocused, so 1–9 answer at once */
const asks = (tid: number) => !!threadOf(tid)?.prompt
const cardBox = () => (!app.reader && app.mode.kind === "thread" && app.cardReply?.tid === app.mode.tid ? app.cardReply : null)

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

const view = () => {
  if (app.viewed?.all !== app.all || app.viewed.ws !== app.ws) app.viewed = { all: app.all, ws: app.ws, v: viewOf(app.all, app.ws) }
  return app.viewed.v
}
const crewOn = () => app.all.workspaces.find((w) => w.id === app.ws)?.shift ?? ""
/** the crew after the one on, in name order; null with fewer than two crews */
const nextCrew = () => { const cs = crewsOf(app.ws); return cs.length > 1 ? next(cs, crewOn()) : null }
/** a click on the header's crew: the next crew goes on */
const toggleShift = () => {
  const to = nextCrew()
  if (app.ws !== null && to) void did(data.shiftSwitch(app.ws, to))
}
/** the crew on, once the workspace has crews; nothing for one with none */
const shiftHeader = () => (crewsOf(app.ws).length ? `⇄ ${crewOn()} crew` : null)
const checkLine = /^#(\d+) (?:verify|landing)/
/** the workline the machine's full check runs on now ("#235 verify …"), or null for a session's own check */
const checkingId = (): number | null => { const m = checkLine.exec(app.all.health?.checks?.running ?? ""); return m ? Number(m[1]) : null }
/** the worklines whose check waits in the queue */
const checkWaitingIds = (): number[] => (app.all.health?.checks?.waiting ?? []).flatMap((l) => { const m = checkLine.exec(l); return m ? [Number(m[1])] : [] })
/** the header's queues: what is checked and what is merged right now */
function queuesHeader(): string | null {
  const c = app.all.health?.checks, mq = app.all.health?.merge_queue ?? []
  const landing = mq.find((m) => m.state === "landing"), queued = mq.filter((m) => m.state === "queued").length
  const parts = [
    c?.running ? (checkingId() ? `✓ checking #${checkingId()}` : "✓ a full check runs") : null,
    c?.waiting.length ? `+${c.waiting.length} waiting` : null,
    landing ? `⤵ landing #${landing.thread_id}` : null,
    queued ? `${queued} queued to land` : null,
  ].filter(Boolean)
  return parts.length ? parts.join(" · ") : null
}
/** what the board reads beyond the snapshot: the leaf cap, and which threads are on the needs list */
const boardCtx = (): BoardCtx => {
  const cap = app.settings?.knobs.find((k) => k.key === "max_leaves")?.value
  return { maxLeaves: typeof cap === "number" ? cap : null, needs: app.needs.flatMap((n) => (n.thread_id ? [n.thread_id] : [])), checking: checkingId(), checkWaiting: checkWaitingIds(), merging: app.all.health?.merge_queue ?? [] }
}
const room = () => { const k = app.ws ?? 0; let r = app.rooms.get(k); if (!r) { app.rooms.set(k, (r = app.wide ? new WideRoom(app.wide) : new RailRoom())); r.setWhimsy(resolveWhim(app.whim)); if (app.petsNow) r.setPets(app.petsNow); if (r instanceof WideRoom) { r.setHome(app.homeNow); r.setTrophies(wonTrophies(app.trophies).length) } r.reactLine = reactFor; r.onSlap = () => { app.ledger = tickSlap(app.ledger) } } return r }
/** the dial moved: remember it and hand every room the resolved dials */
function setWhim(s: WhimState) {
  app.whim = s
  saveWhim(OFFICE, s)
  for (const r of app.rooms.values()) r.setWhimsy(resolveWhim(s))
  changed()
}
const threadOf = (id: number | null) => (id === null ? undefined : app.all.threads.find((t) => t.id === id))
/** the model a seat gets when it sets none of its own: its archetype's, else the server's default */
const inheritedModel = (archetype: string | null) => app.all.archetypes.find((x) => x.name === archetype)?.model || "the server's default"
const wsName = (id = app.ws) => app.all.workspaces.find((w) => w.id === id)?.name ?? "—"
const unread = () => app.feed.filter((x) => x.at > app.trayRead && x.who !== operatorOf(app.all)).length
const changed = () => { app.roomChanged = true; app.imageDirty = true }

/** take the machine's palette if it changed since last look; true when it did */
function followPalette(): boolean {
  try {
    const real = realpathSync(PALETTE), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === app.paletteSeen) return false
    app.paletteSeen = seen
    const j = JSON.parse(readFileSync(real, "utf8")), roles = j.role ?? j
    useRoles(Object.fromEntries(Object.entries(roles).filter(([k, v]) => k in ROLE && typeof v === "string")) as Partial<Record<Role, string>>)
    return true
  } catch { return false }
}

/** take the machine's looks.json if it changed since last look; true when it did */
function followLooks(): boolean {
  try {
    const real = realpathSync(LOOKS), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === app.looksSeen) return false
    app.looksSeen = seen
    useLookOverrides(JSON.parse(readFileSync(real, "utf8")) as Record<string, LookOverride>)
    return true
  } catch { return false }
}

/** take the machine's souls dir if a file came, went or changed; true when it did */
function followSouls(): boolean {
  const seen = soulsSignature(SOULS)
  if (seen === app.soulsSeen) return false
  app.soulsSeen = seen
  useSouls(loadSouls(SOULS))
  return true
}

/**
 * take pets.json if it changed since last look; true when it did. With no file the Sim keeps its
 * unset temperament, so today's room is unchanged byte for byte (the `classic` preset is not neutral).
 */
function followPets(): boolean {
  try {
    const real = realpathSync(PETS_PATH), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === app.petsSeen) return false
    app.petsSeen = seen
    const file = loadPets(real)
    if (!file) return false
    app.petsNow = resolvePets(file)
    for (const r of app.rooms.values()) r.setPets(app.petsNow)
    return true
  } catch { return false }
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
  const v = view(), r = room()
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
    room().converse(said); heard(said); changed()
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
  if (banter) for (const turns of convos.values()) { room().converse(turns); heard(turns); changed() }
  await answers(app.ws)
}
async function answers(w: number) {
  const lobby = lobbyOf(view().threads, w)
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
    changed()
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
    case "tray": app.trayRead = app.feed[0]?.at ?? app.trayRead; writeState(TRAY, app.trayRead); changed(); break
  }
}
/** after a write: say what happened, then look again */
async function did(p: Promise<string>) { app.status = await p; if (app.reader) app.reader.status = app.status; await refresh() }

/** the thread the detail pane is showing, if any */
function openThread(): number | null {
  if (app.reader) return app.reader.tid
  if (app.mode.kind === "thread") return app.mode.tid
  if (app.mode.kind === "person") { const name = app.mode.name, p = crewOf(view()).find((c) => c.name === name); return p?.thread ?? null }
  return null
}
function open(m: Mode) {
  if ((m.kind === "person" || m.kind === "thread" || m.kind === "look" || m.kind === "review" || m.kind === "issue" || m.kind === "play") && m.from === undefined && app.mode.kind !== "home" && app.mode.kind !== "help" && app.mode.kind !== m.kind) m = { ...m, from: app.mode }
  app.status = ""; app.readWhys.delete(cardKey(m)); app.mode = m; app.sel = 0; app.scroll = m.kind === "thread" || m.kind === "person" ? Infinity : 0; app.confirm = null; app.picker = null; app.snapSel = true
  if (m.kind === "thread") { app.picked = m.tid; app.cardReply = { tid: m.tid, ed: app.cardReply?.tid === m.tid ? app.cardReply.ed : new Editor(), focused: !asks(m.tid) } }
  if (m.kind === "person") app.cardOpen = false
  if (m.kind === "person") app.picked = crewOf(view()).find((c) => c.name === m.name)?.thread ?? null
  if (m.kind === "pet" && m.who === "cat") { app.petDraft = structuredClone((app.petsNow ?? resolvePets(loadPets())).cat); app.previewTick = 0 }
  if (m.kind === "look") app.lookDraft = m.hall ? structuredClone(candidateOf(app.hall, hallCtx()).look) : { ...baseLook(m.name), ...overrideFor(m.name) }
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
    case "cat": room().pet(); changed(); return open({ kind: "pet", who: "cat" })
    case "calendar": return open({ kind: "calendar" })
    case "terminal": return void zoomInto(x.tid)
    case "archive": return open({ kind: "archive" })
    case "tray": return open({ kind: "tray" })
    case "beacon": return open({ kind: "triage" })
    case "machine": return hearMachine()
    case "clipboard": return open({ kind: "needs" })
    case "needs": return inbox()
    case "rack": return open({ kind: "health" })
    case "dog": { const r = room(); if (r instanceof WideRoom) r.patDog(); changed(); return open({ kind: "pet", who: "dog" }) }
    case "tv": { const r = room(); if (r instanceof WideRoom) { r.channel(); changed(); draw() } return }
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
  const w = app.ws, projects = view().projects
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
  const box = cardBox()
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
const tidSeg = (id: number): Seg => ({ s: `#${id} `, fg: ROLE.key })
/** open a thread wherever it lives, switching workspace first */
function goThread(id: number, wsId: number | null | undefined) {
  if (wsId != null && wsId !== app.ws) { choose(wsId); app.frame = null }
  app.picker = null
  openReader(id)
}
async function finder() {
  const picks: Pick[] = []
  for (const t of app.all.threads) {
    const where = wsName(t.workspace_id ?? null)
    picks.push({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, { s: `  ${where}${t.lead ? ` · ${t.lead}` : ""}${needsYou(t) ? " · waiting on you" : ""}`, fg: needsYou(t) ? ROLE.attention : ROLE.inactive }], text: `#${t.id} ${t.title} ${where} ${t.lead ?? ""}`, run: () => goThread(t.id, t.workspace_id) })
  }
  picks.push(...ticketPicks(app.all.tickets, wsName, (id) => open({ kind: "ticket", id })))
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

/** what a triage item is: its section, and so which actions it has */
type StuckKind = "blocker" | "check" | "unled"
const oneLine = (t: string) => t.replace(/\s+/g, " ")
/** the triage card's lit row and the issue card share these: the issue verbs are the inbox's issue need's */
/** the whiteboard's marks, worded: one row per state the board draws, and what its colour is */
function boardLegend(): Row[] {
  return [
    { segs: [key("the whiteboard's marks")] },
    ...BOARD_LEGEND.map(([mark, words]): Row => ({ segs: [plain("  "), { s: mark.padEnd(3), fg: ROLE.key, bold: true }, plain(words)] })),
    { segs: [dim("  a mark's colour is its lead's role (their shirt); hover a line for its state in words")] },
  ]
}

function stuckActions(s: data.Stuck, kind: StuckKind): Action[] {
  const after = () => { if (app.mode.kind === "issue" && !app.stuck?.blockers.shown.some((x) => x.issue_id === s.issue_id)) back(); draw() }
  const read: Action = { ...bind("need.v"), run: () => openReader(s.thread_id) }
  if (kind === "blocker" && s.issue_id !== undefined) {
    const id = s.issue_id, ticket = s.ticket_id
    return [
      // owned: the ticket is the fix in flight; the issue comes back to you to close when it is done
      ticket ? { ...bind("need.g.issue"), label: `open ticket #${ticket}`, run: () => open({ kind: "ticket", id: ticket }) } : { ...bind("need.g.issue"), run: () => void did(data.fixIssue(id)).then(after) },
      { ...bind("need.x.issue"), run: () => ask("resolve — why (naming the PR banks the sheriff's postmortem)", (r) => { if (r.trim()) void did(data.resolveIssue(id, r.trim())).then(after) }) },
      read,
    ]
  }
  if (kind === "check") return [...(s.stage === "verify" ? [{ ...bind("need.V.verify_failed"), run: () => void did(data.reverify(s.thread_id)).then(after) }] : []), read]
  return [{ ...bind("need.o.stalled"), run: () => ask(`hand #${s.thread_id} to — a coworker's name`, (r) => { if (r.trim()) void did(data.handOff(s.thread_id, r.trim())).then(after) }) }, read]
}
/** what a stalled need's nudge says to the lead */
const NUDGE = "Nothing has moved here for a while: advance the stage if its work is done, or say what is blocking you."
/** answer with a note: a one-line box naming the options; its first word is an option's number, key or label, the rest goes on as typed — "<key> <note>", the form the server splits */
function answerWithNote(id: number, options: { key: string; label: string }[], after: () => void = () => {}) {
  const opts = options.slice(0, 9)
  ask(`answer with a note — ${opts.map((o, i) => `${i + 1} ${o.label}`).join(" · ")}`, (s) => {
    const m = s.trim().match(/^(\S+)\s*([\s\S]*)$/), w = m?.[1]?.toLowerCase() ?? ""
    const o = opts[Number(w) - 1] ?? opts.find((x) => x.key.toLowerCase() === w || x.label.toLowerCase() === w)
    if (!o) { app.status = "start with the option's number, key or label, then the note"; return draw() }
    void did(data.answer(id, m![2] ? `${o.key} ${m![2]}` : o.key)).then(after)
  })
}
/** what can be done about one waiting item — the inbox's list and its one-at-a-time card share these */
function needActions(n: data.Need): Action[] {
  const tid = n.thread_id ?? null
  const after = () => void refresh()
  // settled by Uqbar: overruling it is the one answer; it goes back to Uqbar, not to you
  if (n.route === "settled") return [{ ...bind("need.u.settled"), run: () => void did(data.overrule(n.key)).then(after) }, ...(tid ? [{ ...bind("need.v"), run: () => openReader(tid) }] : [])]
  const acts: Action[] = [
    ...(n.kind === "gate" && tid ? [{ ...bind("need.A.gate"), run: () => void did(data.approve(tid)).then(after) }] : []),
    ...(n.kind === "dialog" && n.ref ? (n.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void did(data.answer(n.ref!, o.key)).then(after) })) : []),
    ...(n.kind === "ask" && n.ref ? (n.options ?? []).slice(0, 9).map((o): Action => ({ key: o.key, label: o.label, run: () => void did(data.answer(n.ref!, o.key)).then(after) })) : []),
    ...(n.kind === "ask" && n.ref && n.options?.length ? [{ ...bind("need.n.ask"), run: () => answerWithNote(n.ref!, n.options!, after) }] : []),
    ...(n.kind === "ask" && n.ref && n.ask !== "uqbar" ? [{ ...bind("need.u.ask"), run: () => void did(data.handToUqbar(n.ref!)).then(after) }] : []),
    ...(n.kind === "seats" && n.ref ? [{ ...bind("need.1.seats", `raise the cap to ${n.ref}`), run: () => void did(data.settingsEdit("max_leaves", n.ref)).then(after) }] : []),
    ...(n.kind === "job_failed" && n.ref ? [
      { ...bind("need.R.job_failed"), run: () => void did(data.retryJob(n.ref!)).then(after) },
      { ...bind("need.d.job_failed"), run: () => void did(data.dismissJob(n.ref!)).then(after) },
    ] : []),
    ...((n.kind === "question" || n.kind === "mention") && tid ? [{ ...bind("need.r.question"), run: () => reply(tid) }] : []),
    ...(n.kind === "stalled" && tid ? [
      { ...bind("need.n.stalled"), run: () => void did(data.post(tid, NUDGE)).then(after) },
      { ...bind("need.o.stalled"), run: () => ask(`hand #${tid} to — a coworker's name`, (s) => { if (s.trim()) void did(data.handOff(tid, s.trim())).then(after) }) },
      { ...bind("need.x.stalled"), run: () => ask(`close #${tid} — why it is dropped`, (s) => { if (s.trim()) void did(data.closeThread(tid, s.trim())).then(after) }) },
      { ...bind("need.r.stalled"), run: () => reply(tid) },
    ] : []),
    ...(n.kind === "verify_failed" && tid ? [{ ...bind("need.V.verify_failed"), run: () => void did(data.reverify(tid)).then(after) }] : []),
    ...(n.kind === "publish_failed" && tid ? [{ ...bind("need.R.publish_failed"), run: () => void did(data.republish(tid)).then(after) }] : []),
    ...(n.kind === "release_failed" && n.ref ? [{ ...bind("need.R.release_failed"), run: () => void did(data.retryRelease(n.ref!)).then(after) }] : []),
    ...(n.kind === "pr_blocked" && tid ? [
      { ...bind("need.b.pr_blocked"), run: () => void did(data.rebaseLanding(tid)).then(after) },
      { ...bind("need.L.pr_blocked"), run: () => void did(data.relandLanding(tid)).then(after) },
      { ...bind("need.v.pr_blocked", `show me: the thread${n.url ? ` (${n.url})` : ""}`), run: () => openReader(tid) },
    ] : []),
    ...(n.kind === "rollout" && n.ref ? [{ ...bind("need.d.rollout"), run: () => void did(data.dismissRollout(n.ref!)).then(after) }] : []),
    ...(n.kind === "stranded" ? [{ ...bind("need.X.stranded"), run: () => void did(data.retireStranded(n.key)).then(after) }] : []),
    ...(n.kind === "issue" && n.ref ? [{ ...bind("need.g.issue"), run: () => void did(data.fixIssue(n.ref!)).then(after) }] : []),
    ...(n.kind === "issue" && n.ref ? [{ ...bind("need.x.issue"), run: () => ask("resolve — why (naming the PR banks the sheriff's postmortem)", (s) => { if (s.trim()) void did(data.resolveIssue(n.ref!, s.trim())).then(after) }) }] : []),
    ...(n.kind === "publish_failed" && tid ? [{ ...bind("need.d.publish_failed"), run: () => ask("its PR's url — waited on until GitHub merges it", (s) => { if (s.trim()) void did(data.publishedByHand(tid, s.trim())).then(after) }) }] : []),
    ...(n.kind === "no_seat" && n.archetype && n.workspace_id != null ? [{ ...bind("need.h.no_seat", `hire a ${n.archetype}`), run: () => ask(`hire a ${n.archetype} — their name`, (s) => { if (s.trim()) void did(data.hire(n.workspace_id!, s.trim(), n.archetype!)).then(after) }) }] : []),
    ...(n.kind === "no_seat" && tid ? [{ ...bind("need.o.no_seat"), run: () => ask(`hand #${tid} to — a coworker's name`, (s) => { if (s.trim()) void did(data.handOff(tid, s.trim())).then(after) }) }] : []),
    ...(n.kind === "tool_denied" && tid && n.rule && !n.hook ? [{ ...bind("need.A.tool_denied", `allowed it: ${n.rule} is in your own settings (wakes the lead)`), run: () => void did(data.allowed(tid, n.rule!)).then(after) }] : []),
    ...(n.kind === "tool_denied" && tid ? [
      { ...bind("need.r.tool_denied"), run: () => reply(tid) },
      { ...bind("need.B.tool_denied"), run: () => ask(`#${tid} back to build — what to change`, (s) => { if (s.trim()) void did(data.sendBack(tid, "build", s.trim())).then(after) }) },
      { ...bind("need.u.tool_denied"), run: () => void did(data.refusalToUqbar(tid, n.text)).then(after) },
    ] : []),
    ...(n.kind === "quota" && n.workspace_id != null ? (n.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: o.label, run: () => void did(data.shiftSwitch(n.workspace_id!, o.key)).then(after) })) : []),
    ...(n.kind === "quota" ? [
      { ...bind("need.P.quota"), run: () => void did(data.pause("pencils_down")).then(after) },
      { ...bind("need.d.quota"), run: () => void did(data.dismissNeed(n.key)).then(after) },
    ] : []),
    ...(n.level === "decide" || n.kind === "ask" || n.kind === "stalled" ? [{ ...bind("need.d.decide"), run: () => void did(data.dismissNeed(n.key)).then(after) }] : []),
    ...(tid ? [...(n.kind === "pr_blocked" ? [] : [{ ...bind("need.v"), run: () => openReader(tid) }]), { ...bind("need.t"), run: () => void zoomInto(tid) }] : []),
  ]
  return acts.filter((a, i, all) => all.findIndex((b) => b.key === a.key) === i)
}

/** what waits on you: one at a time when anything does — the whole list is a key away */
function inbox() { open(app.needs.length ? { kind: "decide", i: 0 } : { kind: "needs" }) }
/** the answering machine played: the inbox opens, and what was on the machine is heard */
function hearMachine() {
  const keys = app.bySurface.machine.map((n) => n.key)
  open({ kind: "needs" })
  if (keys.length) void did(data.hear(keys))
}
/** a need's one-line name: what kind, and where */
const NEED_KIND: Record<data.Need["kind"], string> = { gate: "gate", question: "question", dialog: "dialog", ask: "asks you", verify_failed: "verify red", stalled: "stalled", mention: "mentioned you", rollout: "rollout", seats: "waits for a seat", job_failed: "job failed", health: "the box", stranded: "stranded work", issue: "issue", blocked: "blocked on a ticket", publish_failed: "not on GitHub", release_failed: "cut failed", pr_blocked: "PR not merging", quota: "out of quota", no_seat: "no seat", tool_denied: "tool refused" }
const NEED_TONE: Record<data.Need["kind"], string> = { gate: ROLE.attention, question: ROLE.key, dialog: ROLE.alarm, ask: ROLE.key, verify_failed: ROLE.alarm, stalled: ROLE.attention, mention: ROLE.body, rollout: ROLE.live, seats: ROLE.attention, job_failed: ROLE.alarm, health: ROLE.alarm, stranded: ROLE.attention, issue: ROLE.alarm, blocked: ROLE.attention, publish_failed: ROLE.alarm, release_failed: ROLE.alarm, pr_blocked: ROLE.alarm, quota: ROLE.attention, no_seat: ROLE.attention, tool_denied: ROLE.alarm }
const needTitle = (n: data.Need) => `${NEED_KIND[n.kind]}${n.thread_id ? ` #${n.thread_id}` : ""} — ${n.title}`
/** main's office has moved past the revision this TUI started on */
const updated = () => !!app.officeRev && !!app.all.revs?.office && app.all.revs.office !== app.officeRev
/** start this TUI over on the new code: hand the terminal back and exec the same command in place */
// every interval this process runs, so a relaunch can stop them all
const timers: ReturnType<typeof setInterval>[] = []
const closers: (() => void)[] = []
const every = (fn: () => unknown, ms: number) => { timers.push(setInterval(fn, ms)) }
/** a timer that, with the terminal unfocused, runs once per `idleMs` instead of every `ms` */
const everyFocused = (fn: () => unknown, ms: number, idleMs = 30_000) => every(paced(() => app.focused, idleMs, fn), ms)

async function relaunch() {
  leave()
  execSelf(selfArgv())
  // exec failed: run the new code as a child, the terminal handed over whole — a parent still
  // ticking draws its own room on alternate frames with the child's (a strobe) and takes its keys
  mute()
  for (const t of timers) clearInterval(t)
  for (const c of closers) c()
  process.stdin.removeAllListeners("data")
  process.stdin.pause()
  const child = Bun.spawn(selfArgv(), { stdio: ["inherit", "inherit", "inherit"], env: process.env })
  process.exit(await child.exited)
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
  ["inbox: everything waiting on you", () => inbox()], ["schedule something", () => newSchedule()],
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
  const lobby = lobbyOf(view().threads, app.ws)
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

/** the verbs on a thread, wherever it is open (its card, a person's, the reader) */
function threadActions(tid: number, inReader = false): Action[] {
  const th = threadOf(tid)
  const prompt = th?.prompt
  const answers = (prompt?.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void did(data.answer(prompt!.id, o.key)) }))
  return [
    ...answers,
    ...(prompt?.options?.length ? [{ ...bind("thread.n"), run: () => answerWithNote(prompt.id, prompt.options!) }] : []),
    ...(inReader ? [] : [{ ...bind("thread.v"), run: () => openReader(tid) }]),
    { ...bind("thread.r"), run: () => reply(tid) },
    ...(studyOf(app.all.threads, app.ws) !== null && studyOf(app.all.threads, app.ws) !== tid ? [{ ...bind("thread.u"), run: () => void did(handToUqbar(app.all.threads, app.ws, tid)) }] : []),
    // the heavy hitter: an @aleph from you calls it in on this thread (Server.Aleph); it answers and leaves
    { ...bind("thread.a"), run: () => ask("call in the Aleph — what should it look at?", (q) => { if (q.trim()) void did(data.post(tid, `@aleph ${q.trim()}`)) }) },
    ...(th?.awaiting && th.stage ? [{ ...bind("thread.A", `approve: ${th.awaiting}`), run: () => void did(data.approve(tid)) }] : []),
    ...(th?.stage ? [{ ...bind("thread.>"), run: () => void did(data.advance(tid)) }] : []),
    ...(th && cardState(view(), th, boardCtx())?.atCap ? [{ ...bind("thread.S"), run: () => { if (app.reader) closeReader(); open({ kind: "settings" }) } }] : []),
    { ...bind("thread.t"), run: () => void zoomInto(tid) },
    { ...bind("thread.g"), run: () => void zoomGit(tid) },
    ...(th?.stage ? [{ ...bind("thread.d"), run: () => void pickDoc(tid) }, { ...bind("thread.R"), run: () => { if (app.reader) closeReader(); open({ kind: "review", tid }) } }] : []),
    {
      ...bind("thread.h"), run: () => {
        const bench = view().bench
        find(`HAND #${tid} OFF TO`, bench.map((c) => ({ segs: [{ s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}${c.name === th?.lead ? " · leads it now" : ""}`, fg: ROLE.inactive }], text: c.name, run: () => { app.picker = null; void did(data.handOff(tid, c.name)) } })))
      },
    },
    {
      ...bind("thread.P"), run: () => {
        find(`MOVE #${tid} TO PROJECT`, view().projects.map((p) => ({ segs: [{ s: p.name, fg: ROLE.prose }], text: p.name, run: () => { app.picker = null; void did(data.move(tid, p.id)) } })))
      },
    },
    ...(th ? [th.paused_at ? { ...bind("thread.P.paused"), run: () => void did(data.pauseThread(tid, "resume")) } : { ...bind("thread.P.running"), run: () => void did(data.pauseThread(tid, "pause")) }] : []),
    { ...bind("thread.x"), run: () => ask2(`close #${tid} as done`, () => did(data.closeThread(tid))) },
    { ...bind("thread.D"), run: () => ask2(`delete #${tid} for good (its worktree goes too, if it loses nothing)`, () => { if (app.reader) closeReader(); back(); void did(data.deleteThread(tid)) }) },
  ]
}

/** the model picker for a seat; the seat card and the cast view share it */
function pickModel(b: Coworker) {
  const w = app.ws, a = view()
  if (w === null) return
  const models = [{ label: `the archetype's (${inheritedModel(b.archetype)})`, value: "inherit" }, ...a.models.map((m) => ({ label: `${m.key}  ${m.thinking} · ${m.harness}`, value: m.key }))]
  find(`${b.name.toUpperCase()}'S MODEL`, models.map((m) => ({ segs: [plain(m.label)], text: m.label, run: () => { app.picker = null; void did(data.retarget(w, b.agent_id, { model: m.value })) } })))
}

/** the persona picker for a seat: make or reroll one, or edit its voice, backstory and quirks */
function pickPersona(b: Coworker) {
  const w = app.ws
  if (w === null) return
  const p = b.persona
  const items: { label: string; run: () => void }[] = [
    p
      ? { label: "draw a new one (reroll)", run: () => ask2(`reroll ${b.name}'s persona — the hand edits go`, () => { app.status = "drawing a new one…"; draw(); void did(data.persona(w, b.agent_id, true)) }) }
      : { label: "make one", run: () => { app.status = "drawing one…"; draw(); void did(data.persona(w, b.agent_id, false)) } },
    ...(p ? [
      { label: "edit the voice", run: () => ask(`${b.name}'s voice`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { voice: s.trim() })) }, { text: p.voice }) },
      { label: "edit the backstory", run: () => ask(`${b.name}'s backstory`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { backstory: s.trim() })) }, { text: p.backstory }) },
      ...(["desk_object", "hobby", "catchphrase", "pet_peeve"] as const).map((k) => ({ label: `edit ${k.replace("_", " ")}`, run: () => ask(`${b.name}'s ${k.replace("_", " ")}`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { quirks: { [k]: s.trim() } })) }, { text: p.quirks[k] }) })),
    ] : []),
  ]
  find(`${b.name.toUpperCase()}'S PERSONA`, items.map((i) => ({ segs: [plain(i.label)], text: i.label, run: () => { app.picker = null; i.run() } })))
}

/** confirm, then let a seat go from this workspace (the agent itself stays) */
function unseatAsk(b: Coworker) {
  ask2(`let ${b.name} go from ${wsName()} (the agent itself stays)`, () => did(data.unseat(b.seat_id, b.name)))
}

/** the verbs on a seated coworker: their model, ask/allow, a clean slate, letting them go */
function seatActions(b: Coworker | undefined): Action[] {
  const w = app.ws
  if (!b || w === null) return []
  return [
    { ...bind("seat.M"), run: () => pickModel(b) },
    { ...bind("seat.y", b.ask === "allow" ? "ask before acting" : "allow without asking"), run: () => void did(data.retarget(w, b.agent_id, { ask: b.ask === "allow" ? "ask" : "allow" })) },
    { ...bind("seat.E"), run: () => pickPersona(b) },
    { ...bind("seat.C"), run: () => ask2(`clear ${b.name}'s context — their session ends, they start fresh when next needed`, () => did(data.clearContext(w, b.agent_id, b.name))) },
    { ...bind("seat.-"), run: () => unseatAsk(b) },
  ]
}

// ── the detail pane ────────────────────────────────────────────────────────────────────────────
/** step a required field forward through its catalogue, wrapping */
function cycleVal<T>(values: readonly T[], cur: T): T { const i = values.indexOf(cur); return values[(i + 1) % values.length]! }
/** step an optional field forward through its catalogue, with undefined ("default"/"none") as one more stop */
function cycleOpt<T>(values: readonly T[], cur: T | undefined): T | undefined {
  const all: (T | undefined)[] = [undefined, ...values], i = all.indexOf(cur)
  return all[(i + 1) % all.length]
}
const dim = (s: string): Seg => ({ s, fg: ROLE.inactive }), plain = (s: string): Seg => ({ s, fg: ROLE.prose })
const key = (s: string): Seg => ({ s, fg: ROLE.key }), pink = (s: string): Seg => ({ s, fg: ROLE.attention })
const live = (s: string): Seg => ({ s, fg: ROLE.live })
const cols = () => process.stdout.columns ?? 80

async function pollPlayer() {
  if (app.playerBusy || Date.now() < app.playerRetry || !(room() instanceof WideRoom)) return
  app.playerBusy = true
  let now: NowPlaying | null = null
  try {
    const p = Bun.spawn(["playerctl", "metadata", "--format", NOW_PLAYING_FORMAT], { stdout: "pipe", stderr: "ignore" })
    const out = await new Response(p.stdout).text()
    if ((await p.exited) === 0) now = parseNowPlaying(out)
  } catch { /* no playerctl */ }
  app.playerBusy = false
  if (!now) app.playerRetry = Date.now() + 30_000
  const rm = room()
  if (rm instanceof WideRoom) rm.setPlayer(now)
}
/** refresh a thread's close look; true when its activity feed moved */
async function pollActivity(tid: number) {
  const was = app.threads.get(tid)?.activity?.at(-1)
  await loadThread(tid)
  const now = app.threads.get(tid)?.activity?.at(-1)
  return was?.at !== now?.at || was?.summary !== now?.summary
}
/** the actions a running thread's card adds: step into the session, flip activity and conversation */
function liveActions(tid: number): Action[] {
  if (!threadOf(tid)?.live) return []
  return [
    { ...bind("live.enter"), run: () => void zoomInto(tid) },
    { ...bind("live.c", app.talkView.has(tid) ? "their activity" : "the conversation"), run: () => { if (!app.talkView.delete(tid)) app.talkView.add(tid); draw() } },
  ]
}
/** an author's colour: you in pink, the server dim, a coworker in their archetype's */
const authorColor = (author: string) =>
  author === operatorOf(app.all) ? ROLE.attention : author === "tlon" ? ROLE.inactive : shirtOf(app.all.bench.find((b) => b.name === author)?.archetype)
const STAGE_RING = ["intent", "spec", "plan", "build", "verify", "review", "landed"]

/** the detail pane's lines under its title, with a one-line foot */
const paneRows = () => (app.g ? Math.max(1, (process.stdout.rows ?? 40) - (app.g.row + app.g.rows + 2) - 2) : DETAIL - 2)
/** the detail pane's text width: the terminal's, less the actions column when there is room for it */
const paneW = () => (cols() >= 80 ? cols() - ACTIONS_W - 1 : cols())
/** a thread's rows for a card; `above`: the card's own rows over them, so the tail still ends in view */
function threadRows(th: Thread | undefined, tid: number, above = 0): Row[] {
  const v = app.threads.get(tid), out: Row[] = []
  out.push({ segs: [key(`#${tid} `), plain(th?.title ?? "")] })
  // a workline's stages as a track (done ones lit, the current one a chip); a plain thread's lead and state
  const cur = th?.stage ? STAGE_RING.indexOf(th.stage) : -1
  out.push({
    segs: [
      ...(th?.stage
        ? STAGE_RING.flatMap((st, i): Seg[] => [...(i ? [dim(" ▸ ")] : []), i === cur ? { s: ` ${st === "landed" && th.landing ? "landing" : st} `, fg: ROLE.ground, bg: th.awaiting ? ROLE.attention : ROLE.key, bold: true } : { s: st, fg: i < cur ? ROLE.live : ROLE.inactive }])
        : [dim("thread")]),
      ...(th?.lead ? [dim("  · "), { s: th.lead, fg: authorColor(th.lead), bold: true }] : []),
      ...(th?.live ? [{ s: `  ${statusGlyph("working")} running`, fg: statusTone("working") }] : []),
    ],
  })
  // a board card's state, and the one thing that moves it
  const st = th && !th.duty && (th.stage || (th.lead && !th.standing)) ? cardState(view(), th, boardCtx()) : null
  if (th && st) { const n = nextStep(th, st); out.push({ segs: [stateSeg(st), { s: st.why, fg: st.kind === "needs" ? ROLE.attention : ROLE.prose }, dim("  → "), key(`${n.key} `), plain(n.label)] }) }
  if (th?.prompt) {
    out.push({ segs: [pink("asks: "), plain(th.prompt.summary)] })
    const pid = th.prompt.id
    th.prompt.options?.forEach((o, i) => out.push({ segs: [key(` ${i + 1} `), plain(o.label)], open: () => did(data.answer(pid, o.key)) }))
  } else if (th?.awaiting && !st) out.push({ segs: [pink(`awaits ${th.awaiting}${th.stage ? " — A approves" : ""}`)] })
  // a running thread's activity, every event the server keeps: the pane opens on the newest and
  // scrolls back (pgup/pgdn, the wheel) — unless you flipped to the conversation
  if (th?.live && !app.talkView.has(tid)) {
    const feed = v?.activity ?? [], live = new Set(app.all.roster.filter((r) => r.thread_id === tid && r.thinking).map((r) => r.agent))
    out.push({ segs: [{ s: " LIVE ", fg: ROLE.ground, bg: ROLE.live, bold: true }, dim("  what they're doing · ⏎ step in · c the conversation")] })
    if (!feed.length) out.push({ segs: [dim("  nothing reported yet — ⏎ steps into their screen")] })
    out.push(...timelineRows(feed, { width: paneW() - 2, colorOf: authorColor, live }))
    return out
  }
  // the conversation's tail, wrapped, as much as fits; `v` reads the whole of it
  const room = paneRows() - above - out.length, tail: Row[] = []
  for (const m of [...(v?.messages ?? [])].reverse()) {
    const lines = wrap(`${m.author}: ${m.body}`, paneW() - 4)
    const tone = m.author === "tlon" ? ROLE.inactive : ROLE.prose
    const rowsOf = lines.map((l, i): Row => ({ segs: i ? [{ s: `  ${l}`, fg: tone }] : [{ s: `${m.author}: `, fg: authorColor(m.author), bold: true }, { s: l.slice(m.author.length + 2), fg: tone }] }))
    tail.unshift(...rowsOf)
    if (tail.length >= room) break
  }
  out.push(...tail.slice(-room))
  if (!v?.messages.length && v?.peek) for (const l of v.peek.split("\n").filter((x) => x.trim()).slice(-4)) out.push({ segs: [dim(l)] })
  return out
}
/** a card state's glyph: ▶ at a desk, ⏸ parked, ◇ idle, ⚑ needs you */
const stateSeg = (st: CardState): Seg => ({ s: `${STATE_GLYPH[st.kind]} `, fg: st.kind === "running" ? ROLE.live : st.kind === "needs" ? ROLE.attention : ROLE.inactive, bold: true })
/** the one thing to do about a board card, by where it stands */
function nextStep(th: Thread, st: CardState): { key: string; label: string } {
  const options = th.prompt?.options?.length ?? 0
  if (st.kind === "needs" && options) return { key: options > 1 ? `1–${Math.min(9, options)}` : "1", label: "answer it" }
  if (st.kind === "needs" && th.awaiting && th.stage) return bind("thread.A", `approve: ${th.awaiting}`)
  if (st.atCap) return bind("thread.S", "raise the cap in settings")
  return bind("thread.v", "open the reader")
}
const ago = (at: string) => {
  const s = Math.max(0, (Date.now() - new Date(at).getTime()) / 1000)
  return s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`
}
const stamp = (at: string) => {
  const d = new Date(at), p = (n: number) => String(n).padStart(2, "0")
  return `${d.toDateString().slice(4, 10)} ${p(d.getHours())}:${p(d.getMinutes())}`
}
const runGlyph = (r: { status: string }): Seg => (r.status === "ok" ? { s: "✓", fg: ROLE.live } : r.status === "failed" ? { s: "✗", fg: ROLE.alarm } : r.status === "interrupted" ? { s: "⊘", fg: ROLE.inactive } : { s: "…", fg: ROLE.key })
const KIND_OF: Record<data.ScheduleKind, string> = { agent: "agent", workline: "workline", script: "script" }
/** a schedule as one row: on or paused, what, when, next, how the last run went */
function scheduleSegs(s: data.Schedule): Seg[] {
  const next = s.next_at ? (new Date(s.next_at).getTime() - Date.now() < 60_000 ? "now" : stamp(s.next_at)) : s.enabled ? "done" : "paused"
  return [
    { s: s.enabled ? "● " : "○ ", fg: s.enabled ? ROLE.live : ROLE.inactive }, dim(KIND_OF[s.kind].padEnd(9)), plain(s.title), dim(`  ${showWhen(s)}${s.agent ? ` · ${s.agent}` : ""}${s.standing ? " · standing" : ""}`),
    key(`  next ${next}`), ...(s.last ? [dim("  last "), runGlyph(s.last), dim(` ${ago(s.last.at)}`)] : []),
  ]
}
/** schedule something new, or change `edit`: what it does (with how), then when */
function newSchedule(edit?: data.Schedule) {
  if (app.ws === null) return
  const w = app.ws, bench = view().bench
  const kinds = [{ label: "an agent run", value: "agent" }, { label: "a workline", value: "workline" }, { label: "a script", value: "script" }]
  const threads = [{ label: "a fresh thread each time", value: false }, { label: "one standing thread", value: true }]
  const who = [{ label: "the workspace's lead", value: null }, ...bench.map((b) => ({ label: b.name, value: b.name }))]
  const cycles: Cycle[] = [
    ...(edit ? [] : [{ name: "run", values: kinds, i: 0 }]),
    { name: "in", values: threads, i: edit?.standing ? 1 : 0 },
    { name: "with (agent runs)", values: who, i: Math.max(0, who.findIndex((x) => x.value === (edit?.agent ?? null))) },
  ]
  ask(edit ? `${edit.title} — what it does` : "schedule — the prompt, the workline's first words, or the shell command", (body, picks) => {
    if (!body.trim()) return
    const [kind, standing, agent] = edit ? [edit.kind, ...picks] : picks
    ask("when — a cron (0 9 * * 1-5, @daily) or a time (14:30, 2026-10-06 14:30, in 2h)", (text) => {
      const when = parseWhen(text)
      if (!when) { app.status = "a schedule needs a when"; return draw() }
      const attrs = { body: body.trim(), standing: standing as boolean, agent: kind === "agent" ? (agent as string | null) : null, ...when }
      void did(edit ? data.schedulePatch(edit.id, attrs) : data.scheduleNew(w, { kind: kind as data.ScheduleKind, ...attrs })).then(loadCard).then(draw)
    }, { text: edit ? showWhen(edit) : "" })
  }, { multiline: true, text: edit?.body, cycles })
}
/** a new routine (title, then how often) */
function newRoutine() {
  if (app.ws === null) return
  const w = app.ws
  ask("routine — what", (title) => {
    if (!title.trim()) return
    ask("every — a cron (0 9 * * *) or @daily / @weekly", (every) => {
      if (every.trim()) void did(data.routineNew(w, title.trim(), every.trim())).then(loadCard).then(draw)
    })
  })
}
function newQuest() {
  if (app.ws === null) return
  const w = app.ws
  ask("quest — what", (title) => { if (title.trim()) void did(data.questNew(w, title.trim())).then(loadCard).then(draw) })
}
const KIND: Record<string, string> = { message: "said", fact: "learned", issue: "raised", question: "asked", check_failed: "check failed", check_passed: "check passed", work_landed: "landed", stage_advanced: "advanced", handoff_opened: "handed off" }

const back1: Action = { ...bind("back.esc"), run: () => { back(); app.roomChanged = true; draw() } }
const pick = <T,>(xs: T[], i: number) => (i >= 0 ? xs[i] : undefined)

/** the card the pane shows: its title, its rows (the left, j/k + enter when any open), its actions (the right, by key) */
function detail(): { title: string; rows: Row[]; actions: Action[]; tint?: string } {
  const a = view(), w = app.ws
  switch (app.mode.kind) {
    case "home": {
      const waiting = a.threads.filter(needsYou)
      const actions: Action[] = [
        { ...bind("home./"), run: () => void finder() }, { ...bind("home.i"), run: inbox },
        { ...bind("home.n"), run: newThread }, { ...bind("home.N"), run: newTicket },
        { ...bind("home.c"), run: () => open({ kind: "crew" }) }, { ...bind("home.t"), run: () => open({ kind: "column", col: 0 }) },
        { ...bind("home.w"), run: () => open({ kind: "tray" }) }, { ...bind("home.!"), run: () => open({ kind: "triage" }) },
        { ...bind("home.a"), run: () => open({ kind: "calendar" }) }, { ...bind("home.o"), run: () => open({ kind: "notes" }) },
        { ...bind("home.b"), run: () => open({ kind: "memory" }) }, { ...bind("home.H"), run: () => open({ kind: "health" }) },
        ...(app.all.life?.[String(w)] ? [{ ...bind("home.L"), run: () => open({ kind: "life" }) }] : []),
        ...(flagOn(app.all, "build_mode") ? [{ ...bind("home.B"), run: () => open({ kind: "build" }) }] : []),
        { ...bind("home.f"), run: () => open({ kind: "archive" }) }, { ...bind("home.W"), run: () => open({ kind: "boss" }) },
        { ...bind("home.S"), run: () => open({ kind: "settings" }) },
        { ...bind("home.h"), run: () => open({ kind: "hall" }) },
        { ...bind("home.cast"), run: () => open({ kind: "cast", tab: "people" }) },
        { ...bind("home.P"), run: () => open({ kind: "store" }) },
        { ...bind("home.q"), run: quit },
      ]
      if (!waiting.length) return { title: "HOME", rows: [{ segs: [dim("nothing waits on you. click someone — or Nina, or Argos — a sticky or the crew board;")] }, { segs: [dim("tab walks the crew, [ ] the workspaces.")] }], actions }
      return { title: `WAITING ON YOU · ${waiting.length}`, rows: waiting.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), pink(`  ${t.prompt?.summary ?? `awaits ${t.awaiting}`}`)], open: () => openReader(t.id) })), actions }
    }
    case "crew": {
      // tabs: each crew, then everyone; the crew on has the live status
      const seats = (app.all.shifts ?? []).filter((x) => x.workspace_id === app.ws)
      const crews = crewsOf(app.ws), tabsOf = [...crews, "all"], on = crewOn(), other = nextCrew()
      if (!tabsOf.includes(app.crewTab)) app.crewTab = "all"
      const live = crewOf(a)
      const inTab = (name: string) => app.crewTab === "all" || seats.find((x) => x.name === name)?.crew === app.crewTab
      const crew = [...live, ...seats.filter((x) => !live.some((c) => c.name === x.name)).map((x) => ({ name: x.name, archetype: x.archetype, status: "off" as SeatStatus, thread: null, title: "", manager: false, lead: false }))].filter((c) => inTab(c.name))
      const shiftOf = (name: string) => seats.find((x) => x.name === name)?.crew
      const tabs: Seg[] = tabsOf.flatMap((t) => [t === app.crewTab ? { s: ` ${tabLabel(t)} `, fg: ROLE.ground, bg: ROLE.key, bold: true } : dim(` ${tabLabel(t)} `), plain(" ")])
      const paused = app.all.pause === "pencils_down" || app.all.pause === "lights_out"
      const rows: Row[] = [{ segs: [...tabs, dim(crews.length ? `   the ${on} crew is on` : "   no crews yet: c puts a seat on one"),
        ...(paused ? badge({ s: app.all.pause === "lights_out" ? "  ◼ lights out " : "  ✎ pencils down ", fg: ROLE.ground, bg: ROLE.attention, bold: true }) : [dim("   at work")])] }]
      for (const g of arrange(crew as any, app.crewSort.cmp, app.crewGroup)) {
        if (g.label !== null) rows.push({ segs: [key(`${g.label} · ${g.items.length}`)] })
        for (const c of g.items as any[]) {
          const b = a.bench.find((x) => x.name === c.name), arch = a.archetypes.find((x) => x.name === c.archetype)
          const model = b?.model ? b.model.model : arch?.model?.split("/").pop() ?? ""
          const off = c.status === "off", shift = shiftOf(c.name)
          rows.push({
            segs: [{ s: `${statusGlyph(c.status)} `, fg: statusTone(c.status) },
              { s: c.name.padEnd(10), fg: off ? ROLE.inactive : shirtOf(c.archetype) }, dim(`${c.manager ? "manager" : c.archetype ?? "?"}${c.lead ? " · lead" : ""}`.padEnd(18)), key(model.padEnd(16)), plain(" "),
              dim((shift === "all" || !shift ? "every crew" : shift).padEnd(12)),
              dim(off && !live.some((l) => l.name === c.name) ? "off shift" : c.thread !== null ? `#${c.thread} ${c.title}` : "on the bench")],
            open: () => open({ kind: "person", name: c.name }), ref: c.name,
          })
        }
      }
      const chosen = a.bench.find((x) => x.name === rows[app.sel]?.ref), seat = seats.find((x) => x.name === rows[app.sel]?.ref)
      const seatTo = seat ? next(tabsOf, seat.crew) : "all"
      const newCrew = () => { if (seat) ask(`put ${seat.name} on a new crew — its name (lowercase, - and _)`, (s) => { if (s.trim()) void did(data.seatShift(seat.seat_id, seat.name, s.trim())) }) }
      return {
        title: `CREW · ${crew.length} · ${tabLabel(app.crewTab)} · by ${app.crewGroup ? `${app.crewGroup.name}, ` : ""}${app.crewSort.name}`,
        rows,
        actions: [{ ...bind("crew.v", `tab: ${tabLabel(next(tabsOf, app.crewTab))}`), run: () => { app.crewTab = next(tabsOf, app.crewTab); app.sel = 0; draw() } },
          ...(seat ? [{ ...bind("crew.c", `${seat.name} on ${seatTo === "all" ? "every crew" : seatTo}`), run: () => void did(data.seatShift(seat.seat_id, seat.name, seatTo)) }, { ...bind("crew.n"), run: newCrew }] : []),
          ...(other ? [{ ...bind("crew.S", `put the ${other} crew on`), run: () => { if (app.ws !== null) void did(data.shiftSwitch(app.ws, other)) } }] : []),
          { ...bind("crew.+"), run: hire },
          paused ? { ...bind("crew.P.paused"), run: () => void did(data.pause("back_to_work")) }
            : { ...bind("crew.P.running"), run: () => void did(data.pause("pencils_down")) },
          ...(app.all.pause !== "lights_out" ? [{ ...bind("crew.L"), run: () => ask2("lights out — pause verify and landing, interrupt every pane", () => void did(data.pause("lights_out"))) }] : []),
          { ...bind("crew.s", `sort: ${app.crewSort.name} → ${next(CREW_SORTS, app.crewSort).name}`), run: () => resort(() => { app.crewSort = next(CREW_SORTS, app.crewSort) }) },
          { ...bind("crew.g", `group: ${app.crewGroup?.name ?? "none"} → ${next(CREW_GROUP_MODES, app.crewGroup)?.name ?? "none"}`), run: () => resort(() => { app.crewGroup = next(CREW_GROUP_MODES, app.crewGroup) }) },
          ...seatActions(chosen), back1],
      }
    }
    case "person": {
      const name = app.mode.name
      const c = crewOf(a).find((x) => x.name === name), b = a.bench.find((x) => x.name === name)
      if (!c) return { title: name.toUpperCase(), rows: [{ segs: [dim("not in this office any more")] }], actions: [back1] }
      const model = b?.model ? `${b.model.provider}/${b.model.model}` : `${inheritedModel(c.archetype)} (archetype's)`
      const where = `${statusGlyph(c.status)} ${statusWord(c.status)}`
      // a pill for where they are, and what they're at mid-turn (the thought bubble's kind)
      const doing = a.roster.find((r) => r.agent === name && r.thinking)?.doing
      const pill = statusTone(c.status)
      const head: Row = {
        segs: [{ s: ` ${c.name} `, fg: ROLE.ground, bg: shirtOf(c.archetype), bold: true }, plain(" "), { s: ` ${where}${doing ? ` · ${doing}` : ""} `, fg: ROLE.ground, bg: pill },
          dim(`  ${c.manager ? "manager" : c.archetype ?? ""}${c.lead ? " · lead" : ""} · ${model} · ${b?.ask ?? "ask (archetype's)"}`)],
      }
      const soul = soulFor(name)
      const cardRows: Row[] = personCard(soul, b?.persona, Math.max(20, cols() - 40), app.cardOpen).map((l) => ({ segs: [l.tone === "key" ? key(l.text) : l.tone === "plain" ? plain(l.text) : dim(l.text)] }))
      const rows: Row[] = [...(c.thread === null ? [head, { segs: [dim("on the bench")] }] : [head, ...threadRows(threadOf(c.thread), c.thread, 1)]), ...cardRows]
      // Scharlach's desk dressing: the nameplate (tertius never agreed to the second part), the mug
      // he bought himself, and the demerit ledger he keeps on the rest of the office
      if (name === SHERIFF && app.cardOpen) {
        rows.push({ segs: [dim("nameplate: "), plain(NAMEPLATE)] }, { segs: [dim("mug: "), plain(MUG)] }, ...ledgerLines(app.ledger, a.bench).map((l) => ({ segs: [dim(l)] })))
      }
      return { title: name.toUpperCase(), rows, tint: shirtOf(c.archetype), actions: [{ ...bind("person.m"), run: () => talk(name) }, { ...bind("person.v"), run: () => openConversation(name) }, ...(c.thread === null ? [] : [{ ...bind("person.w", `read #${c.thread}`), run: () => openReader(c.thread!) }, ...liveActions(c.thread), ...threadActions(c.thread).filter((x) => x.key !== "v")]), ...seatActions(b), { ...bind("person.l"), run: () => open({ kind: "look", name }) }, { ...bind("person.space"), run: () => { app.cardOpen = !app.cardOpen; app.scroll = Infinity; draw() } }, back1] }
    }
    case "thread": {
      const tid = app.mode.tid
      const th = threadOf(tid)
      return { title: `THREAD #${tid}${th?.stage ? ` · workline ${th.stage}` : ""}${th?.paused_at ? " · ⏸ paused" : ""}`, rows: threadRows(th, tid), tint: th?.awaiting || th?.prompt ? ROLE.attention : th?.lead ? authorColor(th.lead) : ROLE.key, actions: [...liveActions(tid), ...threadActions(tid), back1] }
    }
    case "column": {
      const col = boardColumns(a, boardCtx())[app.mode.col]!, items = arrange(col.items, app.colSort.cmp, null)[0]!.items
      // the TICKETS column is a tree: its rows are the open groups' children too, each level in the sort's order
      const titleOf = (x: { id: number }) => a.tickets.find((t) => t.id === x.id)?.title ?? ""
      const levelOrder = <T extends { id: number }>(xs: T[]): T[] => app.colSort.name === "title" ? [...xs].sort((p, q) => titleOf(p).localeCompare(titleOf(q))) : xs
      const tree = app.mode.col === 0 ? treeRows(a, app.expanded, levelOrder) : null
      const it = tree ? pick(tree, app.sel) : pick(items, app.sel), group = tree ? pick(tree, app.sel) : undefined
      const shown = tree ?? items
      const reorder = (dir: "up" | "down"): Action => ({ ...bind(dir === "up" ? "column.K" : "column.J", `move ${dir}`), run: () => { if (it?.act.kind === "ticket") { const was = JSON.stringify(it.act); void did(data.ticketReorder(it.act.id, dir)).then(() => { const at = detail().rows.findIndex((r) => r.ref === was); app.sel = at >= 0 ? at : Math.max(0, Math.min(app.sel + (dir === "up" ? -1 : 1), shown.length - 1)); draw() }) } } })
      return {
        // tickets carry no owner, so the tree has no who order to name
        title: `${col.name} · ${app.mode.col === 0 ? openTotal(a, items.length) : items.length}${app.colSort.name === "board" || (tree && app.colSort.name === "who") ? "" : ` · by ${app.colSort.name}`}`,
        rows: tree ? tree.map((x) => {
          const id = (x.act as { id: number }).id
          return {
            segs: [plain("  ".repeat(x.depth)), dim(x.group ? (x.open ? "▾ " : "▸ ") : "  "), ...(x.header ? [] : [key(`#${id} `)]), plain(x.title), ...(x.flight ? [dim(`  ⚙ on #${x.flight}`)] : [])],
            open: () => x.header ? undefined : x.flight ? act({ kind: "thread", tid: x.flight }) : x.group ? resort(() => { if (x.open) app.expanded.delete(id); else app.expanded.add(id) }) : open({ kind: "ticket", id, from: app.mode }),
            ref: JSON.stringify(x.act),
          }
        }) : items.map((x) => {
          const blocked = x.act.kind === "ticket" && (app.tickets.find((t) => t.id === (x.act as { id: number }).id)?.blocked_by.length ?? 0) > 0
          return {
            segs: [...(x.state ? [stateSeg(x.state)] : []), key(x.act.kind === "ticket" || x.act.kind === "epic" ? `#${x.act.id} ` : x.act.kind === "thread" ? `#${x.act.tid} ` : ""), plain(x.title), dim(`  ${x.stage}${x.who ? ` · ${x.who}` : ""}`),
              ...(x.state ? [{ s: `  ${x.state.why}`, fg: x.state.kind === "needs" ? ROLE.attention : ROLE.inactive }] : x.asks ? [pink("  waiting on you")] : []), ...(blocked ? [pink("  ⊘ blocked")] : [])],
            open: () => x.act.kind === "ticket" || x.act.kind === "epic" ? open({ ...x.act, from: app.mode }) : act(x.act), ref: JSON.stringify(x.act),
          }
        }),
        actions: [
          ...(app.mode.col === 0 ? [{ ...bind("column.n"), run: newTicket }, ...(app.colSort.name === "board" ? [reorder("up"), reorder("down")] : [])] : []),
          ...(group?.group && !group.header ? [{ ...bind("column.space"), run: () => open({ kind: "epic", id: (group.act as { id: number }).id, from: app.mode }) }] : []),
          { ...bind("column.s", `sort: ${app.colSort.name} → ${next(COL_SORTS, app.colSort).name}`), run: () => resort(() => { app.colSort = next(COL_SORTS, app.colSort) }) },
          { ...bind("column.right"), run: () => open({ kind: "column", col: ((app.mode as { col: number }).col + 1) % COLS.length }) },
          back1,
        ],
      }
    }
    case "epic": {
      const id = app.mode.id, ep = a.tickets.find((t) => t.id === id)
      const word = ep?.kind === "initiative" ? "INITIATIVE" : "EPIC"
      if (!ep) return { title: `${word} #${id}`, rows: [{ segs: [dim("finished or gone")] }], actions: [back1] }
      const kids = groupRows(a, id)
      return {
        title: `${word} #${id}${ep.kind === "epic" ? ` · ${ep.done ?? 0}/${ep.total ?? 0}` : ""}`,
        rows: [{ segs: [plain(ep.title)] }, { segs: [dim(`${ep.priority} priority${ep.next ? ` · next #${ep.next.id} ${ep.next.title}` : ""}`)] },
          ...kids.map((k) => {
            const to = k.kind === "ticket" ? ({ kind: "ticket", id: k.id } as const) : ({ kind: "epic", id: k.id } as const)
            return { segs: [key(`#${k.id} `), plain(k.title), dim(`  ${k.kind}`)], open: () => open({ ...to, from: app.mode }), ref: JSON.stringify(to) }
          })],
        actions: [back1],
      }
    }
    case "ticket": {
      const id = app.mode.id
      const tk = a.tickets.find((t) => t.id === id), full = app.tickets.find((t) => t.id === id)
      if (!tk) return { title: `TICKET #${id}`, rows: [{ segs: [dim("started or gone")] }], actions: [back1] }
      // an epic or initiative reached as a ticket (a find, a link) is a group: its card, never "start it"
      if (tk.kind === "epic" || tk.kind === "initiative") { app.mode = { kind: "epic", id, from: app.mode.from }; return detail() }
      const rows: Row[] = [{ segs: [plain(tk.title)] }, { segs: [dim(`${tk.priority} priority${tk.routed ? " · with the manager to staff" : ""}`)] }]
      const parent = tk.epic_id != null ? a.tickets.find((t) => t.id === tk.epic_id) : undefined
      if (parent) rows.push({ segs: [dim("epic "), key(`#${parent.id} `), plain(parent.title)] })
      for (const by of full?.blocked_by ?? []) rows.push({ segs: [pink("⊘ blocked by "), key(`#${by} `), plain(app.tickets.find((t) => t.id === by)?.title ?? "")] })
      if (full?.body) for (const l of wrap(full.body, cols() - 40)) rows.push({ segs: [dim(l)] })
      return {
        title: `TICKET #${id}`, rows,
        actions: [
          { ...bind("ticket.S"), run: () => void did(data.ticketStart(id)) },
          { ...bind("ticket.s"), run: () => void did(data.ticketRoute(id)) },
          { ...bind("ticket.e"), run: () => ask(`ticket #${id} title`, (s) => { if (s.trim()) did(data.ticketPatch(id, { title: s.trim() })) }, { text: tk.title }) },
          {
            ...bind("ticket.b"), run: () => {
              const others = app.tickets.filter((t) => t.id !== id && t.status !== "done")
              find(`#${id} IS BLOCKED BY`, others.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), dim(`  ${t.status}`)], text: `#${t.id} ${t.title}`, run: () => { app.picker = null; void did(data.ticketBlock(id, t.id)) } })))
            },
          },
          ...(full?.blocked_by.length ? [{ ...bind("ticket.u"), run: () => { for (const by of full.blocked_by) void did(data.ticketUnblock(id, by)) } }] : []),
          { ...bind("ticket.K"), run: () => void did(data.ticketReorder(id, "up")) }, { ...bind("ticket.J"), run: () => void did(data.ticketReorder(id, "down")) },
          { ...bind("ticket.d"), run: () => ask2(`delete ticket #${id}`, () => { back(); void did(data.ticketDelete(id)) }) },
          back1,
        ],
      }
    }
    case "calendar": {
      const now = new Date(), first = new Date(now.getFullYear(), now.getMonth(), 1).getDay(), days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
      const booked = new Set((app.cal ?? []).filter((s) => s.enabled).flatMap((s) => s.days))
      const rows: Row[] = [{ segs: [dim("  Su  Mo  Tu  We  Th  Fr  Sa")] }]
      let week: Seg[] = [plain("    ".repeat(first))]
      for (let d = 1; d <= days; d++) {
        const cell = String(d).padStart(3) + (booked.has(d) ? "•" : " ")
        week.push(d === now.getDate() ? { s: cell, fg: ROLE.attention, bold: true } : booked.has(d) ? key(cell) : d < now.getDate() ? dim(cell) : plain(cell))
        if ((first + d) % 7 === 0 || d === days) { rows.push({ segs: week }); week = [] }
      }
      if (!app.cal) rows.push({ segs: [waiting("reading the schedule…")] })
      else if (!app.cal.length) rows.push({ segs: [dim("nothing scheduled yet")] })
      else {
        rows.push({ segs: [key(`SCHEDULED · ${app.cal.length}`)] })
        for (const s of app.cal) rows.push({ segs: scheduleSegs(s), open: () => open({ kind: "runs", id: s.id }), ref: s })
      }
      const s = rows[app.sel]?.ref as data.Schedule | undefined
      return {
        title: now.toLocaleString("en", { month: "long", year: "numeric" }).toUpperCase(), rows,
        actions: [
          { ...bind("calendar.n"), run: () => newSchedule() },
          ...(s ? [
            { ...bind("calendar.e"), run: () => newSchedule(s) },
            { ...bind("calendar.space", s.enabled ? "pause it" : "resume it"), run: () => void did(data.schedulePatch(s.id, { enabled: !s.enabled })).then(loadCard).then(draw) },
            { ...bind("calendar.r"), run: () => void did(data.scheduleRun(s.id)).then(loadCard).then(draw) },
            { ...bind("calendar.d"), run: () => ask2(`remove "${s.title}" and its runs`, () => void did(data.scheduleDelete(s.id)).then(loadCard).then(draw)) },
          ] : []),
          back1,
        ],
      }
    }
    case "life": {
      const s = app.lifeCard
      const rows: Row[] = s ? lifeRows(s).map((r) => ({
        segs: [plain(r.text)],
        open: () => void did(r.kind === "routine" ? data.routineDone(r.id, r.title) : data.questDone(r.id, r.title)).then(loadCard).then(draw),
      })) : [{ segs: [waiting("reading the day…")] }]
      if (s && !rows.length) rows.push({ segs: [dim("nothing due, no open quests")] })
      if (s) rows.unshift({ segs: [s.dump ? plain(`dump · ${data.lines(s.dump.lines)} · edited ${stamp(s.dump.updated_at)}`) : dim("dump · empty — ⏎ to pour it all out")], open: openDump })
      return {
        title: s ? `LIFE · lv ${s.level} · ${s.xp} xp` : "LIFE", rows,
        actions: [{ ...bind("life.E"), run: () => open({ kind: "pages" }) }, { ...bind("life.r"), run: newRoutine }, { ...bind("life.Q"), run: newQuest }, back1],
      }
    }
    case "pages": {
      const rows: Row[] = !app.dumpPages ? [{ segs: [waiting("turning back the pages…")] }]
        : !app.dumpPages.length ? [{ segs: [dim("no earlier pages yet: every save keeps the one it replaced")] }]
        : app.dumpPages.map((p) => ({ segs: [dim(`${stamp(p.at)}  `), plain(data.lines(p.lines)), dim(`  ${p.first}`)], open: () => void readPage(p.id), ref: p }))
      const p = rows[app.sel]?.ref as data.DumpPage | undefined
      const up: Action = { ...bind("pages.esc"), run: () => open({ kind: "life" }) }
      return {
        title: "THE DUMP · EARLIER PAGES", rows,
        actions: [...(p ? [{ ...bind("pages.enter"), run: () => void readPage(p.id) }, { ...bind("pages.R"), run: () => ask2(`put back the ${stamp(p.at)} page (today's is kept as an earlier page)`, () => void restorePage(p.id)) }] : []), up],
      }
    }
    case "runs": {
      const id = app.mode.id, s = app.cal?.find((x) => x.id === id)
      const rows: Row[] = app.board.map((r) => ({
        segs: [runGlyph(r), dim(` ${stamp(r.started_at)} `), plain(r.status.padEnd(8)), dim(r.exit === null ? "" : `exit ${r.exit}  `), r.thread_id ? key(`→ #${r.thread_id}  `) : dim(""), dim((r.output ?? "").replace(/\s+/g, " ").slice(0, 80))],
        open: () => (r.thread_id && !r.output ? openReader(r.thread_id) : open({ kind: "run", id, run: r.id })),
        ref: r,
      }))
      return {
        title: `RUNS · ${s?.title ?? ""}`, rows: rows.length ? rows : [{ segs: [dim("it hasn't run yet")] }],
        actions: [{ ...bind("runs.r"), run: () => void did(data.scheduleRun(id)).then(loadCard).then(draw) }, { ...bind("runs.esc"), run: () => open({ kind: "calendar" }) }],
      }
    }
    case "run": {
      const { id, run } = app.mode
      const r = app.board.find((x) => x.id === run)
      const up: Action = { ...bind("run.esc"), run: () => open({ kind: "runs", id }) }
      if (!r) return { title: "RUN", rows: [{ segs: [dim("gone")] }], actions: [up] }
      const rows: Row[] = [{ segs: [runGlyph(r), dim(` started ${stamp(r.started_at)}${r.finished_at ? `, finished ${stamp(r.finished_at)}` : ", still running"}`), ...(r.thread_id ? [key(`  → #${r.thread_id}`)] : [])] }]
      for (const l of wrap(r.output ?? "(no output)", cols() - 40)) rows.push({ segs: [plain(l)] })
      return { title: `RUN #${r.id} · ${r.status}${r.exit === null ? "" : ` · exit ${r.exit}`}`, rows, actions: [...(r.thread_id ? [{ ...bind("run.t"), run: () => openReader(r.thread_id!) }] : []), up] }
    }
    case "archive": {
      if (!app.archived) return { title: "FILING CABINET", rows: [{ segs: [waiting("opening the drawers…")] }], actions: [back1] }
      const day = (s: string | null) => (s ? s.slice(0, 10) : "")
      const rows: Row[] = [{ segs: [key(`TICKETS DONE · ${app.archived.tickets.length}`)] }]
      for (const t of app.archived.tickets) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${day(t.closed_at)}`)] })
      rows.push({ segs: [key(`THREADS CLOSED · ${app.archived.threads.length}`)] })
      for (const t of app.archived.threads) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${t.stage ?? ""} ${day(t.at)}`)], open: () => openReader(t.id) })
      return { title: "FILING CABINET", rows, actions: [back1] }
    }
    case "notes": {
      const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const rows: Row[] = a.notes.map((n) => ({ segs: [who(n.author), plain(n.body.replace(/\s+/g, " "))] }))
      // the crew's chatter, apart from the notes they work from (their suggestions go in the box)
      if (app.cork.length) rows.push({ segs: [key(`CORKBOARD · ${app.cork.length} — the crew's notes to each other`)] }, ...app.cork.map((n): Row => ({ segs: [dim(`${corkLabel(app.cork, n).padEnd(10)} `), who(n.author), plain(n.body), dim(n.re ? `  (re #${n.re})` : "")], ref: n })))
      return { title: `NOTES · ${a.notes.length}`, rows, actions: [{ ...bind("notes.n"), run: newNote }, back1] }
    }
    case "tray": {
      const rows = arrange(app.feed, app.traySort.cmp, null)[0]!.items.map((x): Row => ({
        segs: [dim(ago(x.at).padStart(4) + " "), x.thread_id ? key(`#${x.thread_id} `) : dim(""), { s: `${x.who ?? ""} ${KIND[x.kind] ?? x.kind.replace(/_/g, " ")} `, fg: x.kind === "issue" || x.kind === "check_failed" ? ROLE.alarm : x.kind === "question" ? ROLE.attention : ROLE.inactive }, plain(x.text.replace(/\s+/g, " "))],
        open: x.thread_id ? () => openReader(x.thread_id!) : undefined, ref: `${x.at}${x.kind}${x.text}`,
      }))
      return {
        title: `IN-TRAY · ${wsName()}${app.traySort.name === "newest" ? "" : ` · by ${app.traySort.name}`}`, rows: rows.length ? rows : [{ segs: [dim("nothing yet")] }],
        actions: [{ ...bind("tray.s", `sort: ${app.traySort.name} → ${next(TRAY_SORTS, app.traySort).name}`), run: () => resort(() => { app.traySort = next(TRAY_SORTS, app.traySort) }) }, back1],
      }
    }
    case "triage": {
      if (!app.stuck) return { title: "TRIAGE", rows: [{ segs: [waiting("looking…")] }], actions: [back1] }
      const rows: Row[] = []
      const section = (name: string, c: data.Capped<data.Stuck>, kind: StuckKind) => {
        if (!c.shown.length) return
        rows.push({ segs: [key(name)] })
        for (const s of c.shown) {
          const segs = kind === "blocker"
            ? [key(`  #${s.issue_id} `), ...(s.ticket_id ? [live(`→ ticket #${s.ticket_id} ${s.ticket_status ?? ""} `)] : []), dim(`${s.created_at ? ago(s.created_at) : ""} ${s.found_by ?? ""}  `), pink(oneLine(s.summary ?? s.text))]
            : [key(`  #${s.thread_id} `), plain(s.title), pink(`  ${s.text}`)]
          rows.push({ segs, open: kind === "blocker" ? () => open({ kind: "issue", id: s.issue_id! }) : () => openReader(s.thread_id), ref: { s, kind } })
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
        actions: [...(at ? stuckActions(at.s, at.kind) : []), back1],
      }
    }
    case "issue": {
      const id = app.mode.id, s = app.stuck?.blockers.shown.find((x) => x.issue_id === id)
      if (!app.stuck) return { title: `ISSUE #${id}`, rows: [{ segs: [waiting("looking…")] }], actions: [back1] }
      if (!s) return { title: `ISSUE #${id}`, rows: [{ segs: [dim("it is no longer an open blocker: fixed, resolved or owned.")] }], actions: [back1] }
      const w = Math.max(20, paneW() - 4), paras = (t: string) => t.split("\n").flatMap((p) => (p.trim() ? wrap(p, w) : [""])).map((l): Row => ({ segs: [plain(l)] }))
      const rows: Row[] = [
        { segs: [dim(`found by ${s.found_by ?? "?"} · ${s.created_at ? ago(s.created_at) : "?"} ago · raised on `), key(`#${s.thread_id} `), plain(s.title)] },
        ...(s.ticket_id ? [{ segs: [live(`being fixed: ticket #${s.ticket_id} (${s.ticket_status ?? "?"}); it comes back to you to close when that ticket is done`)] }] : []),
        { segs: [plain("")] }, { segs: [key("SUMMARY")] }, ...paras(s.summary ?? s.text),
        ...(s.evidence ? [{ segs: [plain("")] }, { segs: [key("EVIDENCE")] }, ...paras(s.evidence)] : []),
      ]
      return { title: `ISSUE #${id}`, tint: ROLE.attention, rows, actions: [...stuckActions(s, "blocker"), back1] }
    }
    case "health": {
      if (!app.rack) return { title: "THE RACK", rows: [{ segs: [waiting("probing…")] }], actions: [back1] }
      const ok = (b: boolean, s: string): Row => ({ segs: [{ s: b ? "● " : "✕ ", fg: b ? ROLE.live : ROLE.alarm }, plain(s)] })
      const up = app.rack.up_s < 3600 ? `${Math.floor(app.rack.up_s / 60)}m` : app.rack.up_s < 86400 ? `${Math.floor(app.rack.up_s / 3600)}h` : `${Math.floor(app.rack.up_s / 86400)}d`
      const queue = queueItems(app.rack, app.settings?.restart_pending ?? false)
      const queueRow = (q: QueueItem): Row => {
        const t = q.thread_id
        const mark = q.kind === "check" || q.kind === "gate" ? { s: "▶ ", fg: ROLE.live } : q.kind === "restart" ? { s: "↻ ", fg: ROLE.attention } : q.kind === "car" ? dim(`   ${q.pos} `) : { s: "⧗ ", fg: ROLE.inactive }
        return { segs: [mark, ...(t ? [tidSeg(t)] : []), plain(q.text), ...(q.kind === "car" && q.lead ? [dim(" (lead)")] : [])], ...(t ? { open: () => goThread(t, null) } : {}) }
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
      return { title: `THE RACK · ${app.rack.state === "ok" ? "all green" : "needs a look"}`, rows, actions: [back1] }
    }
    case "memory": {
      if (!app.shelf) return { title: "MEMORY", rows: [{ segs: [waiting("taking the books down…")] }], actions: [back1] }
      const rows: Row[] = [{ segs: [dim(`${app.shelf.coverage.facts} facts, ${app.shelf.coverage.embedded} embedded · pinned ${app.shelf.coverage.pinned_count} (~${app.shelf.coverage.pinned_tokens} of ${app.shelf.coverage.budget} tokens)`)] }]
      rows.push({ segs: [key(`HABITS TO REVIEW · ${app.shelf.habits.length}`)] })
      for (const h of app.shelf.habits) rows.push({ segs: [dim(`  ${h.by ?? "?"}: `), plain(h.text)], open: () => void 0, ref: { habit: h } })
      rows.push({ segs: [key(`PINNED — every session loads these · ${app.shelf.pinned.length}`)] })
      for (const f of app.shelf.pinned) rows.push({ segs: [dim(`  ${f.id} `), plain(f.text.replace(/\s+/g, " "))], open: () => void 0, ref: { fact: f } })
      const at = rows[app.sel]?.ref as { habit?: data.Memory["habits"][number]; fact?: data.Memory["pinned"][number] } | undefined
      const reload = () => void loadCard().then(draw)
      return {
        title: "MEMORY", rows,
        actions: [
          ...(at?.habit ? [{ ...bind("memory.a"), run: () => void did(data.habit(at.habit!.id, "approve")).then(reload) }, { ...bind("memory.r"), run: () => void did(data.habit(at.habit!.id, "reject")).then(reload) }] : []),
          ...(at?.fact ? [{ ...bind("memory.d"), run: () => ask2(`forget "${at.fact!.text.slice(0, 50)}"`, () => void did(data.forget(at.fact!.id)).then(reload)) }] : []),
          back1,
        ],
      }
    }
    case "build": {
      if (!app.build) { const h = loadFloor(); app.build = startBuild(h.tiles.length ? h : defaultHome(Math.ceil(app.g.floorW / CELL)), OFFICE_ROWS) }
      const b = app.build
      const mutate = (f: (b: Build) => Build): (() => void) => () => {
        app.build = applyBuild(app.build!, f)
        draw()
      }
      const rows: Row[] = [{ segs: [dim("the home is drawn above")] }]
      return {
        title: `BUILD MODE${b.carrying ? ` · carrying ${b.carrying.kind}` : ""}${b.refused ? " · refused — overlap or it would split the floor" : ""}`,
        rows,
        actions: [
          { ...bind("build.up"), run: mutate((x) => move(x, 0, -1)) },
          { ...bind("build.down"), run: mutate((x) => move(x, 0, 1)) },
          { ...bind("build.left"), run: mutate((x) => move(x, -1, 0)) },
          { ...bind("build.right"), run: mutate((x) => move(x, 1, 0)) },
          { ...bind("build.enter", b.carrying ? "drop" : "pick up"), run: mutate((x) => (x.carrying ? drop(x) : pickUp(x))) },
          { ...bind("build.n"), run: mutate((x) => place(x)) },
          { ...bind("build.x"), run: mutate((x) => remove(x)) },
          { ...bind("build.r"), run: mutate((x) => rotate(x)) },
          { ...bind("build.u"), run: mutate((x) => undo(x)) },
          { ...bind("build.esc"), run: () => { back(true); app.roomChanged = true; draw() } },
        ],
      }
    }
    case "boss": {
      const rows: Row[] = [{ segs: [plain(app.all.awaiting ? `${app.all.awaiting} thread(s) wait on you across the office` : "nothing waits on you")] }]
      for (const x of app.all.workspaces) {
        const n = app.all.threads.filter((t) => t.workspace_id === x.id && needsYou(t)).length, s = app.all.triage[String(x.id)] ?? 0
        rows.push({ segs: [key(x.id === app.ws ? "◆ " : "  "), plain(x.name.padEnd(16)), n ? pink(`${n} waiting  `) : dim(""), s ? dim(`${s} issues`) : dim("")], open: () => goWs(x.id) })
      }
      return {
        title: "WORKSPACES", rows,
        actions: [
          {
            ...bind("boss.n"), run: () => {
              const tpl = ["code", "life", "blank"].map((t) => ({ label: t, value: t }))
              ask("new workspace — its name", (s, [t]) => { if (s.trim()) did(data.workspaceNew(s.trim(), t as string)) }, { cycles: [{ name: "from", values: tpl, i: 0 }] })
            },
          },
          { ...bind("boss.e"), run: () => open({ kind: "card" }) },
          { ...bind("boss.S"), run: () => open({ kind: "settings" }) },
          ...(w === null ? [] : [{ ...bind("boss.d"), run: () => ask2(`close ${wsName()} (its threads move to another workspace)`, () => void did(data.workspaceDelete(w))) }]),
          { ...bind("boss.+"), run: hire },
          { ...bind("boss.\\"), run: () => open({ kind: "look", name: MY_LOOK }) },
          back1,
        ],
      }
    }
    case "card": {
      if (!app.card || w === null) return { title: "SETTINGS", rows: [{ segs: [waiting("reading…")] }], actions: [back1] }
      const c = app.card, ring = (xs: string[], x: string) => xs[(xs.indexOf(x) + 1) % xs.length]!
      const reload = () => void loadCard().then(draw)
      const rows: Row[] = [
        { segs: [dim("type  "), plain(c.type), dim("   scope  "), plain(c.scope), dim("   icon  "), plain(c.icon ?? "—")] },
        { segs: [key(`REPOS · ${c.repos.length}`)] },
        ...c.repos.map((r): Row => ({ segs: [plain(`  ${r.path}`), dim(r.remote ? `  ${r.remote}` : "")], open: () => void 0, ref: r })),
      ]
      const repo = rows[app.sel]?.ref as data.WorkspaceCard["repos"][number] | undefined
      return {
        title: `${c.name.toUpperCase()} · SETTINGS`, rows,
        actions: [
          { ...bind("card.T", `type: ${c.type} → next`), run: () => void did(data.workspaceEdit(w, { type: ring(["code", "life", "blank"], c.type) })).then(reload) },
          { ...bind("card.s", `scope: ${c.scope} → next`), run: () => void did(data.workspaceEdit(w, { scope: ring(["project", "machine"], c.scope) })).then(reload) },
          { ...bind("card.I"), run: () => ask("icon", (s) => void did(data.workspaceEdit(w, { icon: s.trim() })).then(reload), { text: c.icon ?? "" }) },
          { ...bind("card.+"), run: () => ask("add a repo — its path", (s) => { if (s.trim()) void did(data.repoAdd(w, s.trim())).then(reload) }) },
          ...(repo ? [{ ...bind("card.-", `remove ${repo.path.split("/").pop()}`), run: () => ask2(`remove ${repo.path} from ${c.name}`, () => void did(data.repoRemove(repo.id)).then(reload)) }] : []),
          back1,
        ],
      }
    }
    case "review": {
      const tid = app.mode.tid, notes = app.reviewNotes.get(tid) ?? []
      if (!app.review) return { title: `REVIEW · #${tid}`, rows: [{ segs: [waiting("reading the branch…")] }], actions: [back1] }
      type At = { path: string; line?: number; side?: "+" | "-" | " "; hunk?: boolean }
      const same = (n: data.ReviewNote, at: At) => n.path === at.path && n.line === at.line && n.side === at.side
      const rows: Row[] = []
      const noteRows = (at: At) => { for (const n of notes) if (same(n, at)) rows.push({ segs: [dim("        "), { s: `✎ ${n.text}`, fg: ROLE.attention }], ref: at }) }
      const noteOn = (at: At) => ask(at.line ? `note on ${at.path}:${at.line}` : `note on ${at.path}`, (s) => {
        if (!s.trim()) return
        app.reviewNotes.set(tid, [...(app.reviewNotes.get(tid) ?? []).filter((n) => !same(n, at)), { path: at.path, line: at.line, side: at.side, text: s.trim() }]); draw()
      }, { text: notes.find((n) => same(n, at))?.text ?? "" })
      for (const f of app.review.files) {
        const at: At = { path: f.path }
        rows.push({ segs: [key(f.path), dim(`  ${f.status}  `), { s: `+${f.added}`, fg: ROLE.live }, plain(" "), { s: `-${f.deleted}`, fg: ROLE.attention }, ...(f.binary ? [dim("  binary")] : [])], open: () => noteOn(at), ref: at })
        noteRows(at)
        for (const h of f.hunks) {
          rows.push({ segs: [dim(h.header)], ref: { path: f.path, hunk: true } })
          for (const l of h.lines) {
            const lineAt: At = { path: f.path, line: l.new ?? l.old ?? undefined, side: l.kind }
            const num = (n: number | null) => (n === null ? "    " : String(n).padStart(4))
            rows.push({ segs: [dim(`${num(l.old)} ${num(l.new)} `), { s: `${l.kind}${l.text}`, fg: l.kind === "+" ? ROLE.live : l.kind === "-" ? ROLE.attention : ROLE.prose }], open: () => noteOn(lineAt), ref: lineAt })
            noteRows(lineAt)
          }
        }
      }
      if (!app.review.files.length) rows.push({ segs: [dim("the branch changes nothing yet")] })
      const here = rows[app.sel]?.ref as At | undefined
      const jump = (dir: 1 | -1, want: (a: At, i: number) => boolean) => {
        for (let i = app.sel + dir; i >= 0 && i < rows.length; i += dir) if (rows[i]?.ref && want(rows[i]!.ref as At, i)) { app.sel = i; return draw() }
      }
      const isFile = (a: At) => !a.line && !a.hunk
      const submit = () => ask(`review #${tid}: a summary (optional) · tab: the verdict`, (s, [verdict]) => {
        const sent = data.reviewSubmit(tid, verdict as string, s, app.reviewNotes.get(tid) ?? [])
        // the notes are kept until the server takes them: a refused submit loses nothing
        void did(sent.then((msg) => { if (!msg.includes(" failed: ")) { app.reviewNotes.delete(tid); back() } return msg }))
      }, { cycles: [{ name: "verdict", values: [{ label: "comment", value: "comment" }, { label: "request changes", value: "changes" }, { label: "approve", value: "approve" }], i: 0 }] })
      return {
        title: `REVIEW · #${tid}${app.review.head ? ` @ ${app.review.head.slice(0, 7)}` : ""} · ${app.review.files.length} files · ${notes.length} notes · ⏎ notes the selected line`,
        rows,
        actions: [
          { ...bind("review.a"), run: () => { if (here && !here.hunk) noteOn(here) } },
          { ...bind("review.A"), run: () => { if (here) noteOn({ path: here.path }) } },
          ...(here && notes.some((n) => same(n, here)) ? [{ ...bind("review.x"), run: () => { app.reviewNotes.set(tid, notes.filter((n) => !same(n, here))); draw() } }] : []),
          { ...bind("review.n"), run: () => jump(1, (a) => !!a.hunk) }, { ...bind("review.p"), run: () => jump(-1, (a) => !!a.hunk) },
          { ...bind("review.N"), run: () => jump(1, isFile) }, { ...bind("review.P"), run: () => jump(-1, isFile) },
          { ...bind("review.s", `submit${notes.length ? ` ${notes.length} notes` : ""}…`), run: submit },
          back1,
        ],
      }
    }
    case "whimsy": {
      const rows: Row[] = whimsyRows(app.whim).map((w) => ({
        segs: [plain(w.label.padEnd(16)), { s: w.value.padEnd(10), fg: ROLE.key }, dim(w.note ?? "")],
        open: () => { setWhim(w.next(app.whim)); draw() },
      }))
      return {
        title: `${whimsyTitle(app.whim)} · ⏎ changes the selected dial`, rows,
        actions: [{ ...bind("whimsy.0"), run: () => { setWhim(resetToPreset(app.whim)); draw() } }, back1],
      }
    }
    case "settings": {
      if (!app.settings) return { title: "THE RUNNING SYSTEM", rows: [{ segs: [waiting("reading…")] }], actions: [back1] }
      const reload = () => void loadCard().then(draw)
      const show = (k: data.Knob) => (k.value === null ? "off" : k.type === "bool" ? (k.value ? "on" : "off") : String(k.value) || "—")
      const change = (k: data.Knob) => {
        if (k.type === "bool") return void did(data.settingsEdit(k.key, !k.value)).then(reload)
        const range = k.type === "int" ? ` (${k.min}–${k.max}${k.nullable ? ", empty: off" : ""})` : ""
        ask(`${k.key}${range}`, (s) => {
          const t = s.trim()
          const v = k.type === "string" ? t : t === "" && k.nullable ? null : Number(t)
          if (typeof v === "number" && !Number.isInteger(v)) return void (app.status = `${k.key} wants a whole number`)
          void did(data.settingsEdit(k.key, v)).then(reload)
        }, { text: k.value === null ? "" : String(k.value) })
      }
      const rows: Row[] = app.settings.knobs.map((k) => ({
        segs: [plain(k.key.padEnd(24)), { s: show(k).padEnd(8), fg: k.value === k.default ? ROLE.prose : ROLE.key }, dim(k.boot ? "on restart  " : "            "), dim(k.doc)],
        open: () => change(k), ref: k,
      }))
      if (app.settings.restart_pending) rows.unshift({ segs: [key("a restart is scheduled"), dim(" — it runs the moment nobody is mid-turn")] })
      return {
        title: "THE RUNNING SYSTEM · ⏎ changes the selected knob", rows,
        actions: [
          { ...bind("settings.Z"), run: () => open({ kind: "whimsy" }) },
          ...(app.settings.restart_pending ? [{ ...bind("settings.x"), run: () => void did(data.restartCancel()).then(reload) }] : []),
          back1,
        ],
      }
    }
    case "needs": {
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
        open: n.thread_id ? () => openReader(n.thread_id!) : undefined, ref: n,
      })
      const TONE = { phone: ROLE.attention, machine: ROLE.body, settled: ROLE.body, clipboard: ROLE.inactive, uqbar: ROLE.inactive }
      const live = app.all.threads.filter((t) => t.live && !t.standing && !app.needs.some((n) => n.thread_id === t.id))
      const section = (label: string, bg: string, note: string): Row => ({ segs: [{ s: ` ${label} `, fg: ROLE.ground, bg, bold: true }, dim(`  ${note}`)] })
      const rows: Row[] = [
        ...inboxSections(app.bySurface).flatMap((s) => [section(s.label, TONE[s.surface], s.note), ...s.items.map(row)]),
        ...(live.length ? [section(`UNDER WAY · ${live.length}`, ROLE.live, "being worked on"), ...live.map((t): Row => ({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, dim(`  ${t.lead ?? ""}${t.stage ? ` · ${t.stage}` : ""}`)], open: () => goThread(t.id, t.workspace_id) }))] : []),
      ]
      const n = rows[app.sel]?.ref as data.Need | undefined
      const acts: Action[] = !n ? [] : [...needActions(n), { ...bind("needs.f"), run: () => open({ kind: "decide", i: Math.max(0, app.needs.indexOf(n)) }) }]
      return {
        title: app.needs.length ? `WAITING ON YOU · ${app.bySurface.counts.phone} on the phone · ${app.bySurface.counts.machine} on the machine · ${app.bySurface.counts.clipboard} on the clipboard` : "WAITING ON YOU",
        tint: app.bySurface.counts.phone ? ROLE.attention : app.needs.length ? ROLE.body : ROLE.live,
        rows: rows.length ? rows : [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }],
        actions: [...acts.filter((a, i, all) => all.findIndex((b) => b.key === a.key) === i), back1],
      }
    }
    case "babel": return {
      title: "THE LIBRARY OF BABEL · a page, at random",
      tint: ROLE.inactive,
      rows: app.mode.page.map((l): Row => ({ segs: [/[a-z]{4,} [a-z]{3,}/.test(l.trim()) && !l.includes(",") ? { s: l, fg: ROLE.attention } : dim(l)] })),
      actions: [{ ...bind("babel.n"), run: openBabel }, back1],
    }
    case "entry": {
      const e = entryOf(a, boardCtx(), app.needs, app.feed, new Date())
      const row = (text: string, x: Act | null): Row => ({ segs: [plain(text)], open: x ? () => act(x) : undefined })
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
        { ...bind("entry.m"), run: () => talk("uqbar") },
        { ...bind("entry.t"), run: () => void zoomInto(study) },
        { ...bind("entry.v"), run: () => openReader(study) },
      ]
      const notes: Action[] = e.footnotes.slice(0, 9).map((f, i) => ({ key: String(i + 1), label: `footnote ${f.mark} — ${f.text}`, run: () => act(f.act) }))
      return { title: e.title, tint: ROLE.inactive, rows, actions: [...verbs, ...notes, back1] }
    }
    case "decide": {
      // one waiting item at a time, everything to decide it on the card; acting moves to the next
      const order = app.needs // phone first, then the machine, then the clipboard
      if (!order.length) return { title: "WAITING ON YOU", tint: ROLE.live, rows: [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }], actions: [back1] }
      const i = Math.min(app.mode.i, order.length - 1), n = order[i]!, tid = n.thread_id ?? null
      const t = tid ? app.all.threads.find((x) => x.id === tid) : undefined
      const step = (d: number) => open({ kind: "decide", i: (i + d + order.length) % order.length })
      const rows: Row[] = [
        { segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(tid ? [tidSeg(tid)] : []), { s: n.title, fg: ROLE.prose, bold: true }], open: tid ? () => openReader(tid) : undefined },
        { segs: [dim(`${n.surface === "clipboard" ? `the crew's: ${clipLabel(n)}` : n.surface === "machine" ? "for your information" : "an answer is owed"} · ${ago(n.at)}${t ? ` · ${t.lead ?? "no lead"}${t.stage ? ` at ${t.stage}` : ""}` : ""}`)] },
        { segs: [plain("")] },
        ...wrap(n.text, paneW() - 4).map((l): Row => ({ segs: [plain(l)] })),
      ]
      return {
        title: `DECIDE · ${i + 1} of ${order.length}`,
        tint: n.surface === "clipboard" ? ROLE.inactive : n.surface === "machine" ? ROLE.body : ROLE.attention,
        rows,
        actions: [...needActions(n), { ...bind("decide.n"), run: () => step(1) }, { ...bind("decide.p"), run: () => step(-1) }, { ...bind("decide.l"), run: () => open({ kind: "needs" }) }, back1],
      }
    }
    case "ideas": {
      const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const rows: Row[] = app.ideas.map((n) => ({ segs: [who(n.author), plain(n.body)], ref: n }))
      const picked = rows[app.sel]?.ref as CorkNote | undefined, w = app.ws
      const gone = (id: number) => { app.ideas = app.ideas.filter((x) => x.id !== id); room().suggestionBox(app.ideas) }
      return {
        title: `SUGGESTION BOX · ${app.ideas.length} · the crew's ideas, yours to file or throw out`, rows: rows.length ? rows : [{ segs: [dim("the box is empty. a coworker drops an idea in it when they see one while working.")] }],
        actions: [
          ...(picked && w !== null ? [
            { ...bind("ideas.t"), run: () => void did(data.ticketFile(w, picked.body)).then(() => data.dropSuggestion(w, picked.id)).then(() => { gone(picked.id); draw() }) },
            { ...bind("ideas.d"), run: () => void data.dropSuggestion(w, picked.id).then(() => { gone(picked.id); draw() }) },
          ] : []),
          back1,
        ],
      }
    }
    case "banter": {
      const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const at = (ms: number) => dim(`${new Date(ms).toTimeString().slice(0, 5)}  `)
      const rows: Row[] = [...app.said].reverse().flatMap((x) => wrap(x.line, paneW() - 14 - x.who.length).map((l, n): Row => ({ segs: n ? [dim(" ".repeat(9 + x.who.length)), plain(l)] : [at(x.at), who(x.who), plain(l)] })))
      return {
        title: `BANTER · the last ${app.said.length} lines said in the room, newest first`,
        rows: rows.length ? rows : [{ segs: [dim("nobody has said anything yet. the crew talks when two of them meet.")] }],
        actions: [back1],
      }
    }
    case "trophies": {
      const rows: Row[] = trophyRows(app.trophies).map((t): Row => ({ segs: [t.won ? pink("★ ") : dim("☆ "), plain(t.name.padEnd(24)), dim(t.note)] }))
      return { title: `TROPHIES · ${wonTrophies(app.trophies).length} won · a cup on the lounge shelf for each`, rows, actions: [back1] }
    }
    case "arcade": {
      // the coworkers' best scores on the cabinets, where the room keeps them
      const r = room(), highs: Row[] = r instanceof WideRoom ? r.highScores().flatMap((h, i): Row[] => (h ? [{ segs: [key(`cabinet ${i + 1}  `), plain(`best ${h.score}`), dim(`  by ${h.name}`)] }] : [])) : []
      const rows: Row[] = GAMES.map((g): Row => (Bun.which(g.cmd) ? { segs: [plain(g.name.padEnd(16)), dim(g.what)], open: () => play(g) } : { segs: [dim(g.name.padEnd(16)), dim("not installed")] }))
      return {
        title: "ARCADE", rows: [{ segs: [plain("the office's cabinets. a game you leave with ctrl+] (to the room) waits for you; quitting it brings the room back.")] }, ...highs, ...rows],
        actions: [back1],
      }
    }
    case "play": { const page2 = app.mode.page === 2; return {
      title: "PLAY", rows: [{ segs: [plain(page2 ? "pick a toy (page 2 of 2)" : "pick a toy")] }],
      actions: [...PLAY_ROWS.filter((b) => ("mode" in b) === page2 && (app.world || !WORLD_ROWS.includes(b.id))).map((b): Action => ({
        ...bind(b.id),
        run: b.id === "play.more" || b.id === "play.first" ? () => { playDo(b.id); draw() } : () => { back(); playDo(b.id); changed(); draw() },
      })), back1],
    } }
    case "pet": {
      const r = room(), wideRoom = r instanceof WideRoom ? r : null
      const doIt = (f: () => unknown) => () => { f(); changed(); draw() }
      // someone mid-turn in this workspace, for a pet to go and cheer on
      const busy = () => app.all.roster.filter((x) => x.workspace_id === app.ws && x.thinking).map((x) => x.agent)
      const cheer = (send: (name: string) => boolean) => doIt(() => { const who = busy(); if (who.length) send(who[Math.floor(random() * who.length)]!) })
      if (app.mode.who === "cat") {
        const draft = (app.petDraft ??= structuredClone((app.petsNow ?? resolvePets(loadPets())).cat))
        const named = Object.entries(TEMPERAMENTS).find(([, t]) => AXES.every((a) => t[a] === draft.temperament[a]))?.[0]
        const row = (label: string, value: string, cycle: () => void): Row => ({ segs: [dim(label.padEnd(12)), plain(value)], open: () => { cycle(); draw() } })
        const beat = previewOf(draft, app.previewTick)
        const rows: Row[] = [
          { segs: [plain(SPECIES_BLURB[draft.species as CatSpecies] ?? SPECIES_BLURB.cat)] },
          { segs: [dim("name".padEnd(12)), plain(draft.name)] },
          row("species", draft.species, () => { draft.species = cycleVal(SLOT_SPECIES.cat, draft.species as CatSpecies) }),
          row("temperament", named ?? "custom", () => { const names = Object.keys(TEMPERAMENTS); draft.temperament = { ...TEMPERAMENTS[names[(names.indexOf(named ?? "") + 1) % names.length]!]! } }),
          ...AXES.map((a) => row(a, dots(draft.temperament[a]), () => { draft.temperament[a] = cycleAxis(draft.temperament[a]) })),
          { segs: [dim("preview".padEnd(12)), plain(`${{ sleep: "z", sit: "·", play: "o", walk: ">" }[beat.mode]} ${beat.line}`)] },
        ]
        return {
          title: `${draft.name.toUpperCase()}`, rows,
          actions: [
            { ...bind("pet.S.cat"), run: () => { savePets({ cat: { species: draft.species, temperament: named ?? { ...draft.temperament } } }); app.petsSeen = ""; followPets(); back(); app.roomChanged = true; draw() } },
            { ...bind("pet.p.cat"), run: doIt(() => r.pet()) },
            { ...bind("pet.z.cat"), run: doIt(() => r.catDo("zoomies")) },
            { ...bind("pet.y.cat"), run: doIt(() => r.catDo("play")) },
            { ...bind("pet.c.cat"), run: doIt(() => r.catDo("come")) },
            { ...bind("pet.s.cat"), run: doIt(() => r.catDo("nap")) },
            { ...bind("pet.b.cat"), run: doIt(() => r.catDo("drink")) },
            { ...bind("pet.u.cat"), run: doIt(() => r.catDo("tub")) },
            ...(busy().length ? [{ ...bind("pet.g.cat"), run: cheer((name) => r.catCheer(name)) }] : []),
            ...(busy().length ? [{ ...bind("pet.l.cat"), run: cheer((name) => r.catLetter(name)) }] : []),
            back1,
          ],
        }
      }
      return {
        title: (app.petsNow ?? resolvePets(loadPets())).dog.name.toUpperCase(), rows: [{ segs: [plain(wideRoom ? "the office dog. good boy." : "the dog lives in the wide room — make the terminal wider to see him.")] }],
        actions: wideRoom ? [
          { ...bind("pet.p.dog"), run: doIt(() => wideRoom.patDog()) },
          { ...bind("pet.w.dog"), run: doIt(() => wideRoom.dogDo("walk")) },
          { ...bind("pet.o.dog"), run: doIt(() => wideRoom.dogDo("office")) },
          { ...bind("pet.s.dog"), run: doIt(() => wideRoom.dogDo("sit")) },
          { ...bind("pet.b.dog"), run: doIt(() => wideRoom.dogDo("bed")) },
          ...(busy().length ? [{ ...bind("pet.g.dog"), run: cheer((name) => wideRoom.dogCheer(name)) }] : []),
          back1,
        ] : [back1],
      }
    }
    case "look": {
      const m = app.mode, name = m.name
      const draft = (app.lookDraft ??= m.hall ? structuredClone(candidateOf(app.hall, hallCtx()).look) : { ...baseLook(name), ...overrideFor(name) })
      const field = (label: string, value: string, cycle: () => void): Row => ({ segs: [dim(label.padEnd(12)), plain(value)], open: () => { cycle(); draw() } })
      const rows: Row[] = [
        { segs: [dim(lookHint(!!m.hall))] },
        field("hair", draft.hair ?? "", () => { draft.hair = cycleVal(HAIR_STYLES, draft.hair!) }),
        field("hair colour", draft.hairRole ?? "", () => { draft.hairRole = cycleVal(HAIR_ROLES, draft.hairRole!) }),
        field("skin", draft.skinRole ?? "default", () => { draft.skinRole = cycleOpt(SKIN_ROLES, draft.skinRole) }),
        field("outfit", draft.outfit ?? "none", () => { draft.outfit = cycleOpt(Object.keys(OUTFIT) as Outfit[], draft.outfit) }),
        field("accessory", draft.accessory ?? "none", () => { draft.accessory = cycleOpt(Object.keys(ACCESSORY) as Accessory[], draft.accessory) }),
        field("build", draft.body ?? "average", () => { draft.body = cycleVal(BODIES, draft.body ?? "average") }),
        ...SLOTS.flatMap((slot) => {
          const spec = draft.parts?.[slot], p = spec ? PARTS[spec.id] : undefined
          return [
            field(slot, spec?.id ?? "none", () => {
              const next = nextPart(slot, spec), parts = { ...draft.parts }
              if (next) parts[slot] = next; else delete parts[slot]
              draft.parts = parts
            }),
            ...Object.keys(p?.dials ?? {}).map((dial) => field(`  ${dial}`, String(dialsOf(p!, spec!.dials)[dial]), () => { draft.parts = { ...draft.parts, [slot]: nextDial(spec!, dial) } })),
          ]
        }),
      ]
      return {
        title: `LOOK · ${name.toUpperCase()}`, rows,
        actions: [
          // ⏎ is the lit row (it cycles a field); save has its own key. A hall candidate has no looks.json entry until hired: its draft goes into hall.json
          { ...bind("look.s"), run: () => { if (m.hall) hallSet(setLook(app.hall, draft as Look)); else { saveLook(name, draft); app.roomChanged = true } app.lookDraft = null; back(); draw() } },
          { ...bind("look.r"), run: () => { Object.assign(draft, rollLook(`${name}:${app.rolls++}`)); draw() } },
          { ...bind("look.e"), run: () => {
            app.editBuf = { front: draft.custom?.front ? [...draft.custom.front] : blankBuf(), side: draft.custom?.side ? [...draft.custom.side] : blankBuf(), back: draft.custom?.back ? [...draft.custom.back] : blankBuf() }
            app.editEntry = { front: [...app.editBuf.front], side: [...app.editBuf.side], back: [...app.editBuf.back] }
            app.editCursor = { x: 0, y: 0 }; app.editScroll = 0
            app.mode = { kind: "look-editor", name, view: "front", from: m.from, hall: m.hall }; app.sel = 0; app.snapSel = true; draw()
          } },
          back1,
        ],
      }
    }
    case "cast": {
      const on = app.mode.tab
      const tab = { ...bind("cast.tab"), run: () => open({ kind: "cast", tab: on === "people" ? "office" : "people" }) }
      if (on === "office") {
        const rows: Row[] = whimsyRows(app.whim).map((w) => ({
          segs: [plain(w.label.padEnd(16)), { s: w.value.padEnd(10), fg: ROLE.key }, dim(w.note ?? "")],
          open: () => { setWhim(w.next(app.whim)); draw() },
        }))
        return { title: `THE CAST · office · ${whimsyTitle(app.whim)}`, rows, actions: [tab, { ...bind("whimsy.0"), run: () => { setWhim(resetToPreset(app.whim)); draw() } }, back1] }
      }
      const seats = a.bench.map((b) => ({ name: b.name, archetype: b.archetype, model: b.model?.model ?? null, voice: b.persona?.voice ?? null, hasSoul: !!soulFor(b.name), hasLook: !!overrideFor(b.name) }))
      const change = (b: Coworker) => {
        const f = CAST_FIELDS[app.castCol]
        if (f === "model") pickModel(b)
        else if (f === "voice") pickPersona(b)
        else if (f === "name" || f === "archetype") { app.status = `a seat's ${f} doesn't change — hire a new one from the hall (h)`; draw() }
        else if (f === "look") open({ kind: "look", name: b.name, from: app.mode })
        else if (f === "soul") openSoul(b.name)
        else if (f === "grade" || f === "specialty") {
          const vocab = f === "grade" ? hallVocab().grades : hallVocab().specialties
          castSet(setTrait(app.cast, b.name, f, nextTrait(vocab, app.cast[b.name]?.[f] ?? "unset"))); draw()
        }
      }
      const reroll = (b: Coworker) => {
        const f = CAST_FIELDS[app.castCol]
        if (f === "look") { saveLook(b.name, { ...(overrideFor(b.name) ?? {}), ...rollLook(`${b.name}:${app.rolls++}`) }); app.roomChanged = true; draw() }
        if (f === "grade" || f === "specialty") { castSet(setTrait(app.cast, b.name, f, rerollTrait(`${b.name}:${app.castRolls++}`, f, hallVocab()))); draw() }
      }
      const rows: Row[] = castRows(seats, app.cast).map((r, i) => ({
        segs: [plain(r.name.padEnd(14)), ...r.cells.slice(1).map((c, j) => i === app.sel && j + 1 === app.castCol ? key(`[${c.value}] `) : (c.editable ? plain : dim)(`${c.value}  `))],
        ref: a.bench[i], open: () => change(a.bench[i]!),
      }))
      const lit = rows[app.sel]?.ref as Coworker | undefined
      if (!rows.length) rows.push({ segs: [dim("nobody on the bench yet — hire from the hall (h)")] })
      const step = (d: number) => { app.castCol = (app.castCol + d + CAST_FIELDS.length) % CAST_FIELDS.length; draw() }
      return {
        title: `THE CAST · people · ${CAST_FIELDS[app.castCol]}`, rows,
        actions: [
          tab, { ...bind("cast.left"), run: () => step(-1) }, { ...bind("cast.right"), run: () => step(1) },
          { ...bind("cast.enter"), run: () => rows[app.sel]?.open?.() },
          ...(lit ? [{ ...bind("cast.y"), run: () => reroll(lit) }, { ...bind("cast.-"), run: () => unseatAsk(lit) }] : []),
          back1,
        ],
      }
    }
    case "hall": {
      const c = candidateOf(app.hall, hallCtx())
      const rows: Row[] = hallRows(c, app.hall.locks).map((r) => ({
        segs: r.segs,
        open: r.lock ? () => { hallSet({ ...app.hall, locks: toggleLock(app.hall.locks, r.lock!.kind, r.lock!.key) }); draw() } : undefined,
      }))
      return {
        title: `HIRING HALL · ${app.hall.seed} · ${app.hall.pile.length} maybe`, rows,
        actions: [
          { ...bind("hall.left"), run: () => { hallSet(pass(app.hall, hallCtx())); draw() } },
          { ...bind("hall.up"), run: () => { hallSet(maybe(app.hall, hallCtx())); draw() } },
          { ...bind("hall.right"), run: () => void hallHire() },
          { ...bind("hall.space"), run: () => rows[app.sel]?.open?.() },
          { ...bind("hall.m"), run: () => open({ kind: "hall-pile" }) },
          { ...bind("hall.e"), run: () => { const w = hallRows(c, app.hall.locks)[app.sel]?.edit; if (w) hallEdit(w) } },
          { ...bind("hall.W"), run: () => void hallDraw() },
          back1,
        ],
      }
    }
    case "store": {
      const taken = storeTaken(), c = storeCandidate(app.store, taken), slot = slotOf(c.species) ?? "cat"
      const occupant = (app.petsNow ?? resolvePets(loadPets()))[slot]
      const rows: Row[] = storeRows(c, app.store.locks, occupant.name, previewOf({ name: c.name, species: c.species, temperament: c.temperament }, app.previewTick).line).map((r) => ({
        segs: r.segs,
        open: r.lock ? () => { storeSet(storeToggle(app.store, r.lock!)); draw() } : undefined,
      }))
      return {
        title: `PET STORE · ${app.store.seed}`, rows,
        actions: [
          { ...bind("store.left"), run: () => { storeSet(shelve(app.store, -1, storeTaken())); draw() } },
          { ...bind("store.right"), run: () => { storeSet(shelve(app.store, 1, storeTaken())); draw() } },
          { ...bind("store.up"), run: () => { storeSet(storePass(app.store, storeTaken())); draw() } },
          { ...bind("store.down"), run: () => { storeSet(storeBack(app.store, storeTaken())); draw() } },
          { ...bind("store.space"), run: () => rows[app.sel]?.open?.() },
          { ...bind("store.e"), run: () => ask("name", (s) => { if (s.trim()) { storeSet(rename(app.store, s.trim())); draw() } }, { text: c.name }) },
          { ...bind("store.enter"), run: storeAdopt },
          back1,
        ],
      }
    }
    case "hall-pile": {
      const rows: Row[] = app.hall.pile.map((e, i) => {
        const c = candidateOf({ ...app.hall, seed: e.seed, overrides: e.overrides, locks: {} }, hallCtx())
        return { segs: [plain(c.name.padEnd(14)), dim(`${c.grade} ${c.archetype} · ${c.specialty} · ${e.seed}`)], ref: i, open: () => { hallSet(bringBack(app.hall, i)); open({ kind: "hall" }) } }
      })
      return {
        title: `MAYBE PILE · ${app.hall.pile.length}`,
        rows: rows.length ? rows : [{ segs: [dim("nobody yet — ↑ in the hall keeps a candidate here")] }],
        actions: [
          { ...bind("hall-pile.x"), run: () => { const i = rows[app.sel]?.ref; if (typeof i === "number") { hallSet({ ...app.hall, pile: dropPile(app.hall.pile, i) }); app.sel = Math.max(0, app.sel - 1); draw() } } },
          { ...bind("hall-pile.esc"), run: () => open({ kind: "hall" }) },
        ],
      }
    }
    case "help": {
      const m = app.mode
      const sect = (name: string, hs: Hint[]): Row[] => hs.length ? [{ segs: [key(name)] }, ...hs.map((h) => ({ segs: [plain("  "), { s: h.key.padEnd(10), fg: ROLE.key, bold: true }, plain(h.label)] }))] : []
      return {
        title: `HELP · ${m.title}`,
        actions: [{ ...bind("help.esc", `back to ${m.title.toLowerCase()}`), run: () => { app.mode = m.from; app.sel = 0; app.scroll = 0; app.snapSel = true; draw() } }],
        rows: [...sect(m.title.toLowerCase(), m.keys), ...sect("everywhere", everywhere()), ...sect("reading a thread (its card's keys work there too)", READER_KEYS), ...(app.world ? sect("the sandbox's play key (it wins over a card's)", PLAY) : TOY_KEYS ? sect("the room's play keys (a card's own key wins)", ROOM_PLAY) : []), ...boardLegend()],
      }
    }
    case "look-editor": {
      const { name, view } = app.mode
      if (!app.editBuf) { app.editBuf = { front: blankBuf(), side: blankBuf(), back: blankBuf() } }
      const draft = (app.lookDraft ?? { ...lookOf(name), ...overrideFor(name) }) as Look
      const paint = paints(shirtOf(null), draft)
      const WIN = 11
      if (app.editCursor.y < app.editScroll + 1) app.editScroll = Math.max(0, app.editCursor.y - 1)
      else if (app.editCursor.y > app.editScroll + WIN - 2) app.editScroll = Math.min(22 - WIN, app.editCursor.y - (WIN - 2))
      const legend: Seg[] = LEGEND_CHARS.flatMap((ch) => [{ s: ch, fg: paint[ch] ?? ROLE.inactive }, plain(" ")])
      const rows: Row[] = [{ segs: legend }]
      const buf = app.editBuf[view]!
      for (let y = app.editScroll; y < Math.min(22, app.editScroll + WIN); y++) {
        const r = buf[y]!, segs: Seg[] = []
        for (let x = 0; x < 12; x++) {
          const ch = r[x]!, color = ch === "." ? ROLE.inactive : (paint[ch] ?? ROLE.inactive), atCursor = y === app.editCursor.y && x === app.editCursor.x
          segs.push(atCursor ? { s: "█", fg: ROLE.ground, bg: color } : { s: ch === "." ? "·" : "█", fg: color })
        }
        rows.push({ segs })
      }
      const hint = (id: KeyId, label: string) => { const k = bind(id, label).key.split(" "); return k.length > 3 ? label : `${k.map(keyName).join("/")} ${label}` }
      rows.push({ segs: [dim([hint("lookedit.view", `view (${view})`), hint("lookedit.mirror", `mirror (${app.editMirror ? "on" : "off"})`), hint("lookedit.paint", "letter paints"), hint("lookedit.clear", "clears"), hint("lookedit.save", "save"), hint("lookedit.discard", "discard")].join(" · "))] })
      return { title: `DRAW · ${name.toUpperCase()}`, rows, actions: [] }
    }
  }
}

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
    out(app.reader.draw(colsN, termRows, threadOf(app.reader.tid), [...threadActions(app.reader.tid, true).map((x) => `${x.key} ${x.label}`), "pgup/pgdn scroll", "esc back", "ctrl+] room"].join(" · ")))
    return
  }
  const a = view()
  const partial = roomOnly && app.paneCursor !== null
  let o = `${ESC}[?2026h${ESC}[?25l`
  // header: the workspace, and what waits elsewhere
  if (!partial) {
    const phone = phoneBar(app.bySurface.counts), usage = usageHeader(app.all, Date.now())
    const head: (Seg & { go?: () => void })[] = [{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(), fg: ROLE.body, bold: true }, key(" › "),
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
  } else if (fresh || app.roomChanged) { app.frame = room0.render(a, { picked: app.lit ?? app.picked, person: app.mode.kind === "person" ? app.mode.name : null, tray: unread(), board: boardCtx(), machine: app.bySurface.counts.machine, clipboard: app.bySurface.clipboard.filter((n) => n.workspace_id == null || n.workspace_id === app.ws) }, measureFor(app.g), app.world?.now()); app.roomChanged = false }
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

const ACTIONS_W = 34
const keyName = (k: string) => ({ space: "␣", enter: "⏎", right: "→", left: "←" })[k] ?? k
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
    const d = detail()
    const add = adder(`card:${app.mode.kind}`)
    title = d.title; app.acts = d.actions; tint = d.tint ?? ROLE.key
    segRows = d.rows.length ? d.rows : [{ segs: [dim(`nothing here yet${add ? ` — ${keyName(add.key)} ${add.label}` : ""}`)] }]
  }
  app.rows = segRows
  const split = app.acts.length > 0 && colsN >= 80
  const leftW = split ? colsN - ACTIONS_W - 1 : colsN
  const box = app.picker || app.input ? null : cardBox(), bv = box?.ed.view(leftW - 4, 4), boxH = bv ? bv.rows.length + 1 : 0
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
  const d = detail()
  open({ kind: "help", from: app.mode, title: d.title, keys: d.actions.map((x) => ({ key: keyName(x.key), label: x.label })) })
}

/** one key, one thing to do with the toy; true when the key was one of them. Off the sandbox only the room's keys, with OFFICE_TOY_KEYS=1 */
function toyKey(k: string): boolean {
  if (!app.world && !roomKey(k, detail().actions.some((x) => x.key === k), TOY_KEYS)) return false
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
  if (isKonami(app.keyLog)) { app.keyLog = []; record(findSecret(app.trophies, "konami")); room().disco(); app.status = "↑↑↓↓←→←→BA — everybody dance"; changed(); return draw() }
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
    if (r === "pass") return threadActions(app.reader.tid, true).find((x) => x.key === k)?.run()
    if (r !== "done") void r.then(draw)
    return draw()
  }
  const box = cardBox()
  if (box?.focused) return boxKey(box, k)
  // a live thread's own ⏎ steps into the session; on any other thread card ⏎ is back into the box
  if (box && k === "enter" && !detail().actions.some((x) => x.key === "enter")) { box.focused = true; return draw() }
  if (toyKey(k)) return
  // the card's own actions first: a key there means what its actions pane says
  const name = k === " " ? "space" : k
  const own = detail().actions.find((x) => x.key === name)
  if (own) return own.run()
  const onActions = actionsFocused()
  switch (k) {
    case "q": case "ctrl-c": return quit()
    case "esc": back(); app.roomChanged = true; return draw()
    case "[": return stepWs(-1)
    case "]": return stepWs(1)
    case "tab": case "backtab": {
      const crew = crewOf(view())
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
    case "p": room().pet(); changed(); return draw()
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
  const box = cardBox()
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
  zoomOn(target, `#${tid} ${threadOf(tid)?.lead ?? target.window} · terminal`)
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
  zoomOn({ socket: OWN_TMUX, session, window: "lazygit" }, `#${tid} ${threadOf(tid)?.lead ?? ""} · git`)
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
/** the arcade's games: terminal games, played wherever the machine has installed them */
const GAMES = [
  { name: "Space Invaders", cmd: "ninvaders", what: "ninvaders" },
  { name: "Pac-Man", cmd: "myman", what: "myman" },
  { name: "Moon Buggy", cmd: "moon-buggy", what: "jump the craters" },
  { name: "Snake", cmd: "nsnake", what: "nsnake" },
  { name: "Tetris", cmd: "bastet", what: "bastet, which picks the worst block on purpose" },
  { name: "2048", cmd: "2048-in-terminal", what: "slide and merge" },
  { name: "Minesweeper", cmd: "freesweep", what: "freesweep" },
  { name: "Sudoku", cmd: "nudoku", what: "nudoku" },
  { name: "Solitaire", cmd: "ttysolitaire", what: "klondike" },
  { name: "Doom", cmd: "doom", what: "Freedoom, drawn in text" },
]
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
async function main() {
  if (!process.stdin.isTTY) { console.error("office: needs a terminal"); process.exit(1) }
  followPalette()
  followLooks()
  followSouls()
  followPets()
  enter()
  process.on("uncaughtException", (e) => { leave(); console.error(e); process.exit(1) })
  let pending = "", detected = false
  const ready = new Promise<void>((res) => {
    process.stdin.on("data", (b: Buffer) => {
      if (app.zoom) return zoomInput(b)
      const { inputs, rest } = tokenize(pending + b.toString("utf8"))
      pending = rest
      for (const i of inputs) {
        if (i.t === "cell") app.cell = { w: i.w, h: i.h }
        else if (i.t === "graphics") app.kitty = process.env.OFFICE_GRAPHICS !== "blocks" && i.ok
        else if (i.t === "da") { if (!detected) { detected = true; res() } }
        else if (!detected) continue
        else if (i.t === "key") onKey(i.key)
        else if (i.t === "paste") onPaste(i.text)
        else if (i.t === "focus") { app.focused = i.on; app.looks.focus(i.on); if (!i.on) stampLooked(); draw() }
        else if (i.t === "mouse") onMouse(i)
      }
    })
    setTimeout(() => { if (!detected) { detected = true; res() } }, 500)
  })
  query()
  await ready
  // tmux eats the graphics protocol unless told to pass it through; blocks there by default
  if (process.env.TMUX && process.env.OFFICE_GRAPHICS !== "kitty") app.kitty = false
  layoutScreen()
  process.stdout.on("resize", () => {
    if (app.zoom) { app.zoom.view.resize(cols(), Math.max(2, (process.stdout.rows ?? 24) - 1)); return drawZoom() }
    query(); setTimeout(() => { layoutScreen(); draw() }, 150)
  })
  await refresh()
  if (app.world && process.env.OFFICE_PLAY_INTRO === "1" && !readState(PLAY_SEEN)) { writeState(PLAY_SEEN, "1"); open({ kind: "play" }) }
  everyFocused(refresh, 10_000)
  everyFocused(pollPlayer, 2000)
  everyFocused(watchTrophies, 1000)
  let sec = 0
  every(() => { app.looks.tick(1); if (app.focused && ++sec % 5 === 0) stampLooked(); if (app.focused && !app.reader && !app.zoom && app.notes.some((n) => { const a = app.looks.alpha(n); return a < 1 && a > FLOOR })) draw() }, 1000)
  every(() => { if (app.focused && ((app.mode.kind === "pet" && app.petDraft) || app.mode.kind === "store")) { app.previewTick += 10; draw() } }, 1000)
  every(() => { if (app.focused && app.bySurface.counts.phone > 0) draw() }, 1000) // the phone rings: its glyph shakes once a second
  const followFiles = () => { if ([followPalette(), followLooks(), followSouls(), followPets(), followHall(), followStore(), followCast()].some(Boolean)) { app.frame = null; draw() } }
  const real = (p: string) => { try { return realpathSync(p) } catch { return p } }
  const files = [PALETTE, LOOKS, PETS_PATH, HALL, STORE, CAST]
  const watched = watchDirs([...files, ...files.map(real)].map((f) => dirname(f)).concat(SOULS), followFiles)
  closers.push(watched.close)
  if (!watched.ok) everyFocused(followFiles, 1000)
  // another surface (the desktop's alert) asks to show a thread: open it, once per request, ignoring
  // what was asked before this TUI started
  let seenFocus = (await data.focus())?.at ?? 0
  everyFocused(async () => {
    const f = await data.focus()
    if (!f || f.at <= seenFocus) return
    seenFocus = f.at
    if (app.zoom) leaveZoom()
    goThread(f.thread_id, threadOf(f.thread_id)?.workspace_id)
    openReader(f.thread_id, {}, false)
  }, 1000, 5000)
  // a card showing a running coworker keeps their activity current
  everyFocused(() => {
    const tid = openThread()
    if (tid !== null && !app.zoom && !app.reader && threadOf(tid)?.live && !app.talkView.has(tid)) void pollActivity(tid).then((moved) => { if (moved) draw() })
  }, 1000)
  // the room's clock: 10 Hz, drawn only when it changed. The room's time is counted in these ticks, so
  // it always steps; it is the repaint (a whole frame each) that costs a room nobody watches a core:
  // none while the terminal is unfocused (the return to focus draws), 2 Hz while the office is calm
  // (paused, or no coworker live)
  const animate = process.env.OFFICE_NO_ANIMATE !== "1" // tests boot the TUI with it off: no frame to wait on
  let beat = 0, frames = 0, stale = false
  const calm = () => app.all.pause === "pencils_down" || app.all.pause === "lights_out" || !app.all.threads.some((t) => t.live)
  every(() => {
    if (animate && !app.reader && room().step(view())) { changed(); stale = true }
    // the header and the pane catch up once a second; the frames between repaint the room alone
    if (stale && app.focused && (++beat % 5 === 0 || !calm())) { stale = false; paint(++frames % 10 !== 0) }
  }, 100)
}
main()
