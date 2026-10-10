// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { babelPage, isKonami, KONAMI } from "../kit/eggs"
import { mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { personaLines } from "../kit/persona"
import { boardColumns, busiest, cardState, COLS, crewOf, epicChildren, needsYou, STATE_GLYPH, viewOf, type Act, type BoardCtx, type CardState } from "../kit/crew"
import { cycleAxis, dots, previewOf, resolvePets, TEMPERAMENTS, type PetSetting, type Pets } from "../kit/pets"
import { AXES } from "../kit/temperament"
import { drop, move, pickUp, place, remove, rotate, startBuild, undo, type Build } from "../kit/home"
import { renderHome } from "../kit/homeart"
import { mailbox } from "../kit/mailbox"
import { loadSouls, soulFor, soulLines, soulsSignature, useSouls } from "../kit/souls"
import { overrideFor, trimCustom, useLookOverrides, type LookOverride } from "../kit/looks"
import { ROLE, useRoles, type Role } from "../kit/palette"
import { lifeHeader, lifeRows } from "../kit/life"
import { nextPart, SLOTS } from "../kit/parts"
import { ACCESSORY, BODIES, HAIR_STYLES, HAIR_ROLES, lookOf, rollLook, OUTFIT, paints, shirtOf, SKIN_ROLES, type Accessory, type Look, type Outfit } from "../kit/sprites"
import { parseNowPlaying } from "../kit/stereo"
import { EMPTY, flagOn, type Agents, type LifeStatus, type CorkNote, type Coworker, type Thread, type ThreadView } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"
import { BAND, OFF_DOOR, OFF_W, WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import { say, lobbyOf, replies } from "./talk"
import * as data from "./data"
import { PLAY, toy } from "./sandbox"
import { Editor, wrap } from "./editor"
import { rank } from "./fuzzy"
import { ticketPicks } from "./finder"
import { applyBuild, loadHome } from "./home"
import { loadPets, PETS_PATH, savePets } from "./pets"
import { geometry, hitAt, kittyImage, measureFor, textLayer, type Geometry } from "./paint"
import { Reader } from "./reader"
import { timelineRows } from "./timeline"
import { footLines, follow as followSel, offset, type Hint, type Window } from "./pane"
import { cells, enter, ESC, leave, line, mute, out, query, tokenize, type Input, type Seg } from "./term"
import { rows as vtRows, TerminalView, type Target } from "./terminal"
import { centerViewport, clipFrame, panViewport, type Viewport } from "./viewport"
import { parseWhen, showWhen } from "./when"
import { arrange, CREW_GROUPS, CREW_SORTS, next, type Sort } from "./order"

type Mode =
  | { kind: "home" } | { kind: "crew" } | { kind: "notes" } | { kind: "boss" } | { kind: "archive" }
  | { kind: "person"; name: string } | { kind: "thread"; tid: number }
  | { kind: "column"; col: number } | { kind: "ticket"; id: number } | { kind: "epic"; id: number } | { kind: "calendar" } | { kind: "life" }
  | { kind: "tray" } | { kind: "triage" } | { kind: "health" } | { kind: "memory" } | { kind: "card" }
  | { kind: "runs"; id: number } | { kind: "run"; id: number; run: number } | { kind: "pet"; who: "cat" | "dog" } | { kind: "arcade" } | { kind: "ideas" } | { kind: "needs" } | { kind: "decide"; i: number } | { kind: "babel"; page: string[] }
  | { kind: "build" } | { kind: "settings" }
  | { kind: "look"; name: string } | { kind: "look-editor"; name: string; view: "front" | "side" | "back" }
/** a detail-pane row, and what a click (or Enter, on the selected one) does with it */
type Row = { segs: Seg[]; open?: () => void; ref?: unknown }
/** a choice an input cycles through with tab (the project a thread goes in, a template, …) */
type Cycle = { name: string; values: { label: string; value: unknown }[]; i: number }
type Prompt = { label: string; ed: Editor; submit: (s: string, picks: unknown[]) => void; cycles?: Cycle[]; focus: number }
/** one row of the finder: what it shows, what it is matched on, what picking it does */
type Pick = { segs: Seg[]; text: string; run: () => void }

const DETAIL = 14 // the detail pane's rows, title included: fixed, so nothing below the room moves
const STATE_DIR = join(process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"), "tlon")
const STATE = join(STATE_DIR, "office-workspace")
const TRAY = join(STATE_DIR, "office-tray") // when you last read the in-tray
const OPERATOR = process.env.TLON_OPERATOR ?? "andrew"
// the machine's palette, when it hands one in: `{ "role": { "<role>": "#rrggbb", … } }` (or the bare
// map). A link here that the machine repoints on a theme switch is followed within a second.
const PALETTE = process.env.TLON_PALETTE ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/palette.json")
// per-agent look overrides, same poll shape as PALETTE above
const LOOKS = process.env.TLON_LOOKS ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/looks.json")

// per-coworker SOUL.md files, one `<name>.md` each, polled like LOOKS
const SOULS = process.env.TLON_SOULS ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/souls")

const readState = (p: string) => { try { return readFileSync(p, "utf8").trim() } catch { return "" } }
const writeState = (p: string, s: string) => { try { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, s) } catch { /* a read-only home: it just won't remember */ } }

/** read-merge-write one agent's entry into looks.json, same shape as cli.ts's importer */
function saveLook(name: string, draft: LookOverride) {
  let all: Record<string, LookOverride> = {}
  try { all = JSON.parse(readFileSync(LOOKS, "utf8")) } catch { /* no file yet */ }
  all[name] = draft
  writeState(LOOKS, JSON.stringify(all, null, 2))
  looksSeen = "" // our own write: make the next poll re-read it instead of treating it as already seen
}

// `--sandbox`: the TUI on a made-up world (tui/sandbox.ts) instead of the server
const world = process.argv.includes("--sandbox") || process.env.OFFICE_SANDBOX === "1" ? toy() : null
if (world) data.useFake(world)

let all: Agents = { ...EMPTY, note: "…" }
let ws: number | null = Number(readState(STATE)) || null
// the wide room when the terminal is wide enough for it (`wide` is its width), else the rail room
let wide: number | null = null
const rooms = new Map<number, RailRoom | WideRoom>()
const threads = new Map<number, ThreadView>()
let mode: Mode = { kind: "home" }, picked: number | null = null, sel = 0
let tip = "", status = ""
/** the header's clickable spans, in 1-based columns, as last drawn */
let headHits: { from: number; to: number; go: () => void }[] = []
// how the list cards are ordered (`s` sort, `g` group): kept across visits
const CREW_GROUP_MODES = [null, ...CREW_GROUPS]
const CREW_TABS = ["day", "night", "all"] as const
const TAB_LABEL = { day: "☼ day", night: "☾ night", all: "everyone" } as const
let crewTab: (typeof CREW_TABS)[number] = "all"
let crewSort = CREW_SORTS[0]!, crewGroup: (typeof CREW_GROUP_MODES)[number] = null
type Item = ReturnType<typeof boardColumns>[number]["items"][number]
const COL_SORTS: Sort<Item>[] = [{ name: "board", cmp: () => 0 }, { name: "title", cmp: (a, b) => a.title.localeCompare(b.title) }, { name: "who", cmp: (a, b) => (a.who ?? "~").localeCompare(b.who ?? "~") }]
let colSort = COL_SORTS[0]!
const TRAY_SORTS: Sort<data.Activity[number]>[] = [{ name: "newest", cmp: () => 0 }, { name: "thread", cmp: (a, b) => (a.thread_id ?? Infinity) - (b.thread_id ?? Infinity) }, { name: "who", cmp: (a, b) => (a.who ?? "~").localeCompare(b.who ?? "~") }]
let traySort = TRAY_SORTS[0]!
/** step an ordering, keeping the cursor on the row (by its `ref`) it was on */
function resort(step: () => void) {
  const was = rows[sel]?.ref
  step()
  const at = was === undefined ? -1 : detail().rows.findIndex((r) => r.ref === was)
  if (at >= 0) sel = at
  draw()
}
let input: Prompt | null = null
// a card just opened: its cursor goes to the first row you can act on, once there is one
let snapSel = false
let confirm: { label: string; run: () => void } | null = null
// the look card/editor's draft, not yet saved to looks.json; set on open, cleared on close/save
let lookDraft: LookOverride | null = null
let rolls = 0
// the pet card's draft (Nina's temperament, not yet saved to pets.json) and the preview row's clock
let petDraft: PetSetting | null = null, previewTick = 0
let editBuf: Record<"front" | "side" | "back", string[]> | null = null
let editEntry: Record<"front" | "side" | "back", string[]> | null = null
let editCursor = { x: 0, y: 0 }
let editScroll = 0
let editMirror = true
const LEGEND_CHARS = ["h", "f", "k", "s", "p", "b", "y", "c", "g", "e", "w", "r", "o"]
const blankBuf = () => Array.from({ length: 22 }, () => ".".repeat(12))
let picker: { title: string; q: Editor; items: Pick[]; sel: number } | null = null
let reader: Reader | null = null
let cell: { w: number; h: number } | null = null, kitty = process.env.OFFICE_GRAPHICS === "kitty"
let g: Geometry, frame: Frame | null = null, sentImage = false, rows: Row[] = []
/** the floor's visible window: centred on the office zone while `follow`, fixed where a manual pan left it otherwise */
let viewport: Viewport = { x: 0, y: 0, w: 0, h: 0 }, follow = true, panned = false
let drag: { col: number; row: number } | null = null
/** build mode's state, kept across a leave-and-reopen so you come back where you left it */
let build: Build | null = null
// the room moved (re-render its frame); its art changed (resend the image)
let roomChanged = true, imageDirty = true, homeShown = false
let homeNow = loadHome()

// what the open card reads, fetched when it opens and on every refresh while it stays open
let archived: data.Archive | null = null, feed: data.Activity = [], stuck: data.Triage | null = null, rack: data.Health | null = null
/** the office corkboard: the crew's chatter to each other, newest first */
let cork: CorkNote[] = []
/** everything waiting on you (`Server.Office.Needs`), blocking first */
let needs: data.Need[] = []
/** the office revision this TUI started on: when main's moves past it, R reloads */
let officeRev: string | null | undefined
/** the suggestion box: corkboard ideas the banter wrote in a coworker's voice (never a request), for you to file or throw out */
let ideas: CorkNote[] = []
let shelf: data.Memory | null = null, tickets: data.BoardTicket[] = [], card: data.WorkspaceCard | null = null, settings: data.Settings | null = null
let lifeCard: LifeStatus | null = null
let cal: data.Schedule[] | null = null, board: data.Run[] = []
let trayRead = readState(TRAY)

const view = () => viewOf(all, ws)
/** a click on the header's shift: the other shift starts */
const toggleShift = () => {
  if (ws === null) return
  void did(data.shiftSwitch(ws, all.workspaces.find((w) => w.id === ws)?.shift === "night" ? "day" : "night"))
}
/** the shift on, once anyone is on a shift of their own; nothing for a workspace with no shifts set */
const shiftHeader = () =>
  (all.shifts ?? []).some((x) => x.workspace_id === ws && x.crew !== "all")
    ? all.workspaces.find((w) => w.id === ws)?.shift === "night" ? "☾ night shift" : "☼ day shift"
    : null
/** what the board reads beyond the snapshot: the leaf cap, and which threads are on the needs list */
const boardCtx = (): BoardCtx => {
  const cap = settings?.knobs.find((k) => k.key === "max_leaves")?.value
  return { maxLeaves: typeof cap === "number" ? cap : null, needs: needs.flatMap((n) => (n.thread_id ? [n.thread_id] : [])) }
}
const room = () => { const k = ws ?? 0; let r = rooms.get(k); if (!r) { rooms.set(k, (r = wide ? new WideRoom(wide) : new RailRoom())); if (petsNow) r.setPets(petsNow); if (r instanceof WideRoom) r.setHome(homeNow) } return r }
const threadOf = (id: number | null) => (id === null ? undefined : all.threads.find((t) => t.id === id))
const wsName = (id = ws) => all.workspaces.find((w) => w.id === id)?.name ?? "—"
const unread = () => feed.filter((x) => x.at > trayRead && x.who !== OPERATOR).length
const changed = () => { roomChanged = true; imageDirty = true }

let paletteSeen = ""
/** take the machine's palette if it changed since last look; true when it did */
function followPalette(): boolean {
  try {
    const real = realpathSync(PALETTE), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === paletteSeen) return false
    paletteSeen = seen
    const j = JSON.parse(readFileSync(real, "utf8")), roles = j.role ?? j
    useRoles(Object.fromEntries(Object.entries(roles).filter(([k, v]) => k in ROLE && typeof v === "string")) as Partial<Record<Role, string>>)
    return true
  } catch { return false }
}

let looksSeen = ""
/** take the machine's looks.json if it changed since last look; true when it did */
function followLooks(): boolean {
  try {
    const real = realpathSync(LOOKS), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === looksSeen) return false
    looksSeen = seen
    useLookOverrides(JSON.parse(readFileSync(real, "utf8")) as Record<string, LookOverride>)
    return true
  } catch { return false }
}

let soulsSeen = ""
/** take the machine's souls dir if a file came, went or changed; true when it did */
function followSouls(): boolean {
  const seen = soulsSignature(SOULS)
  if (seen === soulsSeen) return false
  soulsSeen = seen
  useSouls(loadSouls(SOULS))
  return true
}

let petsSeen = "", petsNow: Pets | null = null
/**
 * take pets.json if it changed since last look; true when it did. With no file the Sim keeps its
 * unset temperament, so today's room is unchanged byte for byte (the `classic` preset is not neutral).
 */
function followPets(): boolean {
  try {
    const real = realpathSync(PETS_PATH), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === petsSeen) return false
    petsSeen = seen
    const file = loadPets(real)
    if (!file) return false
    petsNow = resolvePets(file)
    for (const r of rooms.values()) r.setPets(petsNow)
    return true
  } catch { return false }
}

function choose(id: number | null) {
  if (id !== ws) { feed = []; card = null }
  ws = id
  writeState(STATE, id === null ? "" : String(id))
}
/** the last workspace you had open, while it exists; else Machine; else the busiest */
function settleWorkspace() {
  if (!all.ok) return
  if (ws !== null && all.workspaces.some((w) => w.id === ws)) return
  ws = all.workspaces.find((w) => w.name.toLowerCase() === "machine")?.id ?? busiest(all)
}
function stepWs(d: 1 | -1) {
  const list = all.workspaces
  if (!list.length) return
  const i = list.findIndex((w) => w.id === ws)
  goWs(list[(i + d + list.length) % list.length]!.id)
}
function goWs(id: number) { choose(id); back(true); frame = null; void refresh() }

// ── staying current ───────────────────────────────────────────────────────────────────────────
async function refresh() {
  const before = all, beforeNeeds = needs
  let knobs: data.Settings | null
  ;[all, needs, knobs] = await Promise.all([data.status(), data.needs(), data.settings()])
  settings = knobs ?? settings
  if (officeRev === undefined && all.ok) officeRev = all.revs?.office ?? null
  settleWorkspace()
  if (all.ok && before.ok) tellNews(before, beforeNeeds)
  const tid = openThread()
  await Promise.all([tid !== null ? loadThread(tid) : null, reader ? reader.reload() : null, loadCard(), loadFeed()])
  await chatter()
  draw()
}
/** what changed since the last look that you'd want to hear about even with the office in the back */
function tellNews(before: Agents, beforeNeeds: data.Need[]) {
  // only what stops work rings: a new blocking item; several at once are one notification
  const was = new Set(beforeNeeds.map((n) => n.key))
  const fresh = needs.filter((n) => n.level === "blocking" && !was.has(n.key))
  if (fresh.length) out("\x07") // something new waits on you: the terminal's bell
  if (fresh.length === 1) notify(needTitle(fresh[0]!), fresh[0]!.text)
  else if (fresh.length > 1) notify(`${fresh.length} things wait on you`, fresh.map(needTitle).join(" · "))
  if (before.health?.state === "ok" && all.health?.state === "warn") notify("tlon needs a look", all.health.problems.join("; "))
}
/** a desktop notification (OSC 777, as ghostty, kitty, WezTerm and foot take it) */
function notify(title: string, body: string) {
  const clean = (s: string) => s.replace(/[;\x07\x1b]/g, " ").slice(0, 200)
  out(`${ESC}]777;notify;${clean(title)};${clean(body)}${ESC}\\`)
}
async function loadFeed() {
  if (ws === null) return
  const seen = new Set(feed.map((x) => `${x.at}${x.kind}${x.text}`)), first = !feed.length
  feed = (await data.activity(ws)) ?? feed
  // a first run starts with the tray read, not with everything that ever happened in it
  if (!trayRead && feed[0]) { trayRead = feed[0].at; writeState(TRAY, trayRead) }
  if (!first) for (const x of feed) if ((x.kind === "issue" || x.kind === "question") && !seen.has(`${x.at}${x.kind}${x.text}`)) notify(`${x.kind} raised${x.who ? ` by ${x.who}` : ""}`, x.text)
}
// the office's small talk: each line the server's banter wrote, once, as a balloon over its speaker
const heard = new Set<string>()
async function chatter() {
  if (ws === null) return
  room().hear(await data.pets(ws))
  cork = await data.corkboard(ws)
  room().pinboard(cork)
  ideas = await data.suggestions(ws)
  room().suggestionBox(ideas)
  for (const b of await data.banter(ws)) {
    const k = `${b.at} ${b.agent}`
    if (heard.has(k)) continue
    heard.add(k)
    room().say(b.agent, b.line)
    changed()
  }
  await answers(ws)
}
/** the operator's answers: a lobby post answering you is a balloon over its author, and a notification when a card covers the room */
let answered: Set<number> | null = null
async function answers(w: number) {
  const lobby = lobbyOf(view().threads, w)
  const v = lobby === null ? null : await data.thread(lobby)
  if (!v) return
  const fresh = replies(v.messages, OPERATOR).filter((r) => !answered?.has(r.id))
  const first = answered === null
  answered ??= new Set()
  for (const r of fresh) {
    answered.add(r.id)
    if (first) continue
    room().say(r.agent, r.line)
    if (mode.kind !== "home") notify(`${r.agent} answered`, r.line)
    changed()
  }
}
async function loadThread(tid: number) { const v = await data.thread(tid); if (v) threads.set(tid, v) }
/** the open card's own read, if it has one */
async function loadCard() {
  if (ws === null) return
  const w = ws
  switch (mode.kind) {
    case "archive": archived = await data.archive(w); break
    case "triage": stuck = await data.triage(w); break
    case "health": rack = await data.health(); break
    case "memory": shelf = await data.memory(w); break
    case "ticket": case "epic": case "column": tickets = (await data.board(w)) ?? tickets; break
    case "card": card = await data.workspaceCard(w); break
    case "settings": settings = await data.settings(); break
    case "calendar": cal = await data.schedules(w); break
    case "life": lifeCard = (await data.life(w)) ?? lifeCard; break
    case "runs": case "run": board = (await data.runs(mode.id)) ?? board; cal ??= await data.schedules(w); break
    case "tray": trayRead = feed[0]?.at ?? trayRead; writeState(TRAY, trayRead); changed(); break
  }
}
/** after a write: say what happened, then look again */
async function did(p: Promise<string>) { status = await p; if (reader) reader.status = status; await refresh() }

/** the thread the detail pane is showing, if any */
function openThread(): number | null {
  if (reader) return reader.tid
  if (mode.kind === "thread") return mode.tid
  if (mode.kind === "person") { const name = mode.name, p = crewOf(view()).find((c) => c.name === name); return p?.thread ?? null }
  return null
}
function open(m: Mode) {
  mode = m; sel = 0; scroll = m.kind === "thread" || m.kind === "person" ? Infinity : 0; confirm = null; picker = null; snapSel = true
  if (m.kind === "thread") picked = m.tid
  if (m.kind === "person") picked = crewOf(view()).find((c) => c.name === m.name)?.thread ?? null
  if (m.kind === "pet" && m.who === "cat") { petDraft = structuredClone((petsNow ?? resolvePets(loadPets())).cat); previewTick = 0 }
  if (m.kind === "look") lookDraft = { ...lookOf(m.name), ...overrideFor(m.name) }
  const tid = openThread()
  void Promise.all([tid !== null ? loadThread(tid) : null, loadCard()]).then(draw)
  draw()
}
/** Esc: a card back to home, home to nothing picked; `all` drops both at once */
function back(everything = false) {
  if (everything || mode.kind === "home") picked = null
  mode = { kind: "home" }; sel = 0; scroll = 0; confirm = null; picker = null; lookDraft = null; petDraft = null
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
    case "rack": return open({ kind: "health" })
    case "dog": { const r = room(); if (r instanceof WideRoom) r.patDog(); changed(); return open({ kind: "pet", who: "dog" }) }
    case "tv": { const r = room(); if (r instanceof WideRoom) { r.channel(); changed(); draw() } return }
    case "arcade": return open({ kind: "arcade" })
    case "ideas": return open({ kind: "ideas" })
    case "weather": status = all.weather ? `outside: ${all.weather.desc.toLowerCase()}${all.weather.temp_c === null ? "" : `, ${all.weather.temp_c}°C`}` : "no word on the weather"; return draw()
  }
}

// ── writing: the inputs ─────────────────────────────────────────────────────────────────────────
function ask(label: string, submit: Prompt["submit"], opts: { multiline?: boolean; text?: string; cycles?: Cycle[] } = {}) {
  input = { label, ed: new Editor(opts.text ?? "", !!opts.multiline), submit, cycles: opts.cycles, focus: 0 }
  draw()
}
function newThread() {
  if (ws === null) return
  const w = ws, projects = view().projects
  ask("new thread — your first words; the first line is its title", (s, [project, kind]) => { if (s.trim()) did(data.newThread(w, s.trim(), project as number | null, kind as data.Kind)) }, {
    multiline: true,
    cycles: [
      { name: "project", values: [{ label: "the default project", value: null }, ...projects.map((p) => ({ label: p.name, value: p.id }))], i: 0 },
      { name: "as", values: [{ label: "a thread", value: "thread" }, { label: "a workline (from intent)", value: "workline" }, { label: "a spike (straight to build)", value: "spike" }], i: 0 },
    ],
  })
}
function newTicket() {
  if (ws === null) return
  const w = ws
  ask("new ticket", (s) => { if (s.trim()) did(data.ticketFile(w, s.trim())) })
}
function newNote() {
  if (ws === null) return
  const w = ws
  ask("a note for the corkboard", (s) => { if (s.trim()) did(data.note(w, s.trim())) }, { multiline: true })
}
/** speak to a coworker (`to`) or, with null, to the office — the speech composer */
function talk(to: string | null) {
  if (ws === null) return
  const w = ws
  ask(to ? `say to ${to}` : "say to the office", (s) => { void did(say(view().threads, w, to, s)) }, { multiline: true })
}
function reply(tid: number) { openReader(tid, true) }
function hire() {
  if (ws === null) return
  const w = ws, kinds = all.archetypes.map((x) => ({ label: `${x.name}${x.meta ? " (manager)" : x.read_only ? " (read-only)" : ""}`, value: x.name }))
  if (!kinds.length) { status = "no archetypes to hire from"; return draw() }
  ask("hire — their name", (s, [arch]) => { if (s.trim()) did(data.hire(w, s.trim(), arch as string)) }, { cycles: [{ name: "as", values: kinds, i: Math.max(0, kinds.findIndex((k) => k.value === "builder")) }] })
}

// ── the finder ─────────────────────────────────────────────────────────────────────────────────
function find(title: string, items: Pick[]) { picker = { title, q: new Editor("", false), items, sel: 0 }; draw() }
const tidSeg = (id: number): Seg => ({ s: `#${id} `, fg: ROLE.key })
/** open a thread wherever it lives, switching workspace first */
function goThread(id: number, wsId: number | null | undefined) {
  if (wsId != null && wsId !== ws) { choose(wsId); frame = null }
  picker = null
  openReader(id, false)
}
async function finder() {
  const picks: Pick[] = []
  for (const t of all.threads) {
    const where = wsName(t.workspace_id ?? null)
    picks.push({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, { s: `  ${where}${t.lead ? ` · ${t.lead}` : ""}${needsYou(t) ? " · waiting on you" : ""}`, fg: needsYou(t) ? ROLE.attention : ROLE.inactive }], text: `#${t.id} ${t.title} ${where} ${t.lead ?? ""}`, run: () => goThread(t.id, t.workspace_id) })
  }
  picks.push(...ticketPicks(all.tickets, wsName, (id) => open({ kind: "ticket", id })))
  for (const w of all.workspaces) picks.push({ segs: [{ s: "workspace ", fg: ROLE.inactive }, { s: w.name, fg: ROLE.body }], text: `workspace ${w.name}`, run: () => goWs(w.id) })
  for (const c of all.bench.filter((b) => b.workspace_id === ws)) picks.push({ segs: [{ s: "coworker ", fg: ROLE.inactive }, { s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}`, fg: ROLE.inactive }], text: `${c.name} ${c.archetype}`, run: () => open({ kind: "person", name: c.name }) })
  for (const [label, run] of VERBS) picks.push({ segs: [{ s: "do ", fg: ROLE.inactive }, { s: label, fg: ROLE.prose }], text: label, run })
  picks.push({ segs: [{ s: "the Library of Babel", fg: ROLE.inactive }], text: "babel library borges", run: () => openBabel() })
  find("FIND — a thread, a workspace, a coworker, a verb", picks)
  const closed = await data.history()
  if (picker?.title.startsWith("FIND") && closed) {
    for (const t of closed) picker.items.push({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.inactive }, { s: `  closed ${t.at.slice(0, 10)}`, fg: ROLE.inactive }], text: `#${t.id} ${t.title} closed`, run: () => goThread(t.id, t.workspace_id) })
    draw()
  }
}
/** everything across the workspaces that waits on you, then what's being worked on */
/** a page of the Library of Babel, the width of the card */
function openBabel() { open({ kind: "babel", page: babelPage(DETAIL - 2, Math.max(20, paneW() - 4)) }) }

/** what can be done about one waiting item — the inbox's list and its one-at-a-time card share these */
function needActions(n: data.Need): Action[] {
  const tid = n.thread_id ?? null
  const after = () => void refresh()
  const acts: Action[] = [
    ...(n.kind === "gate" && tid ? [{ key: "A", label: "approve", run: () => void did(data.approve(tid)).then(after) }] : []),
    ...(n.kind === "dialog" && tid ? (n.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void did(data.post(tid, o.key)).then(after) })) : []),
    ...(n.kind === "ask" && n.ref ? (n.options ?? []).slice(0, 9).map((o): Action => ({ key: o.key, label: o.label, run: () => void did(data.answerAsk(n.ref!, o.key)).then(after) })) : []),
    ...(n.kind === "seats" && n.ref ? [{ key: "1", label: `raise the cap to ${n.ref}`, run: () => void did(data.settingsEdit("max_leaves", n.ref)).then(after) }] : []),
    ...(n.kind === "job_failed" && n.ref ? [
      { key: "R", label: "run it again", run: () => void did(data.retryJob(n.ref!)).then(after) },
      { key: "d", label: "dismiss", run: () => void did(data.dismissJob(n.ref!)).then(after) },
    ] : []),
    ...((n.kind === "question" || n.kind === "mention") && tid ? [{ key: "r", label: "reply", run: () => reply(tid) }] : []),
    ...(n.kind === "verify_failed" && tid ? [{ key: "V", label: "run verify again", run: () => void did(data.reverify(tid)).then(after) }] : []),
    ...(n.kind === "rollout" && n.ref ? [{ key: "d", label: "done", run: () => void did(data.dismissRollout(n.ref!)).then(after) }] : []),
    ...(tid ? [{ key: "v", label: "read the thread", run: () => openReader(tid, false) }, { key: "t", label: "look over their shoulder", run: () => void zoomInto(tid) }] : []),
  ]
  return acts.filter((a, i, all) => all.findIndex((b) => b.key === a.key) === i)
}

/** what waits on you: one at a time when anything does — the whole list is a key away */
function inbox() { open(needs.length ? { kind: "decide", i: 0 } : { kind: "needs" }) }
/** a need's one-line name: what kind, and where */
const NEED_KIND: Record<data.Need["kind"], string> = { gate: "gate", question: "question", dialog: "dialog", ask: "asks you", verify_failed: "verify red", mention: "mentioned you", rollout: "rollout", seats: "waits for a seat", job_failed: "job failed", stranded: "stranded work" }
const NEED_TONE: Record<data.Need["kind"], string> = { gate: ROLE.attention, question: ROLE.key, dialog: ROLE.alarm, ask: ROLE.key, verify_failed: ROLE.alarm, mention: ROLE.body, rollout: ROLE.live, seats: ROLE.attention, job_failed: ROLE.alarm, stranded: ROLE.attention }
const needTitle = (n: data.Need) => `${NEED_KIND[n.kind]}${n.thread_id ? ` #${n.thread_id}` : ""} — ${n.title}`
/** main's office has moved past the revision this TUI started on */
const updated = () => !!officeRev && !!all.revs?.office && all.revs.office !== officeRev
/** start this TUI over on the new code: hand the terminal back, run the same command, leave with its code */
// every interval this process runs, so a relaunch can stop them all
const timers: ReturnType<typeof setInterval>[] = []
const every = (fn: () => unknown, ms: number) => { timers.push(setInterval(fn, ms)) }

async function relaunch() {
  leave()
  // hand the terminal over whole: a parent still ticking draws its own room on alternate frames
  // with the child's (a strobe) and takes keys meant for it
  mute()
  for (const t of timers) clearInterval(t)
  process.stdin.removeAllListeners("data")
  process.stdin.pause()
  const child = Bun.spawn([process.execPath, ...process.argv.slice(1)], { stdio: ["inherit", "inherit", "inherit"], env: process.env })
  process.exit(await child.exited)
}

/** the verbs the finder offers by name — the same ones the keys reach */
const VERBS: [string, () => void][] = [
  ["new thread", () => newThread()], ["new ticket", () => newTicket()], ["new note", () => newNote()], ["hire a coworker", () => hire()],
  ["in-tray: what just happened", () => open({ kind: "tray" })], ["triage: what is stuck", () => open({ kind: "triage" })],
  ["health: the service and its box", () => open({ kind: "health" })], ["memory: pinned facts and habits", () => open({ kind: "memory" })],
  ["workspaces", () => open({ kind: "boss" })], ["this workspace's settings and repos", () => open({ kind: "card" })],
  ["settings: the running system's knobs, and a restart", () => open({ kind: "settings" })],
  ["crew", () => open({ kind: "crew" })], ["shifts", () => open({ kind: "crew" })], ["calendar", () => open({ kind: "calendar" })], ["filing cabinet", () => open({ kind: "archive" })],
  ["inbox: everything waiting on you", () => inbox()], ["schedule something", () => newSchedule()],
  ["Nina, the cat", () => open({ kind: "pet", who: "cat" })], ["Argos, the dog", () => open({ kind: "pet", who: "dog" })],
  ["the arcade", () => open({ kind: "arcade" })], ["the suggestion box", () => open({ kind: "ideas" })],
]

// ── the reader: a thread full-screen ────────────────────────────────────────────────────────────
function openReader(tid: number, compose: boolean) {
  picked = tid
  reader = new Reader(tid, { load: (before) => (before ? data.page(tid, before) : data.thread(tid)), send: (body) => data.post(tid, body), operator: OPERATOR, redraw: () => draw() }, compose)
  const v = threads.get(tid)
  if (v) reader.take(v)
  void reader.reload().then(draw)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
  draw()
}
function closeReader() {
  reader = null
  out(`${ESC}[?25l`)
  layoutScreen(); draw()
}
/** something you can do from a card: its key, what it says in the actions pane, what it does */
type Action = { key: string; label: string; run: () => void }
const ask2 = (label: string, run: () => void) => { confirm = { label, run }; draw() }

/** the verbs on a thread, wherever it is open (its card, a person's, the reader) */
function threadActions(tid: number, inReader = false): Action[] {
  const th = threadOf(tid)
  const answers = (th?.prompt?.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void did(data.post(tid, o.key)) }))
  return [
    ...answers,
    ...(inReader ? [] : [{ key: "v", label: "read it all", run: () => openReader(tid, false) }]),
    { key: "r", label: "reply", run: () => reply(tid) },
    ...(th?.awaiting && th.stage ? [{ key: "A", label: `approve: ${th.awaiting}`, run: () => void did(data.approve(tid)) }] : []),
    ...(th?.stage ? [{ key: ">", label: "advance the workline", run: () => void did(data.advance(tid)) }] : []),
    ...(th && cardState(view(), th, boardCtx())?.atCap ? [{ key: "S", label: "raise the cap (settings)", run: () => { if (reader) closeReader(); open({ kind: "settings" }) } }] : []),
    { key: "t", label: "look over their shoulder", run: () => void zoomInto(tid) },
    { key: "g", label: "git (lazygit)", run: () => void zoomGit(tid) },
    ...(th?.stage ? [{ key: "d", label: "read its docs (spec, plan…)", run: () => void pickDoc(tid) }] : []),
    {
      key: "h", label: "hand off to…", run: () => {
        const bench = view().bench
        find(`HAND #${tid} OFF TO`, bench.map((c) => ({ segs: [{ s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}${c.name === th?.lead ? " · leads it now" : ""}`, fg: ROLE.inactive }], text: c.name, run: () => { picker = null; void did(data.handOff(tid, c.name)) } })))
      },
    },
    {
      key: "P", label: "move to project…", run: () => {
        find(`MOVE #${tid} TO PROJECT`, view().projects.map((p) => ({ segs: [{ s: p.name, fg: ROLE.prose }], text: p.name, run: () => { picker = null; void did(data.move(tid, p.id)) } })))
      },
    },
    { key: "x", label: "close as done", run: () => ask2(`close #${tid} as done`, () => did(data.closeThread(tid))) },
    { key: "D", label: "delete for good", run: () => ask2(`delete #${tid} for good (its worktree goes too, if it loses nothing)`, () => { if (reader) closeReader(); back(); void did(data.deleteThread(tid)) }) },
  ]
}

/** the verbs on a seated coworker: their model, ask/allow, a clean slate, letting them go */
function seatActions(b: Coworker | undefined): Action[] {
  const w = ws, a = view()
  if (!b || w === null) return []
  return [
    {
      key: "M", label: "model…", run: () => {
        const models = [{ label: `the archetype's (${a.archetypes.find((x) => x.name === b.archetype)?.model ?? "?"})`, value: "inherit" }, ...a.models.map((m) => ({ label: `${m.key}  ${m.thinking} · ${m.harness}`, value: m.key }))]
        find(`${b.name.toUpperCase()}'S MODEL`, models.map((m) => ({ segs: [plain(m.label)], text: m.label, run: () => { picker = null; void did(data.retarget(w, b.agent_id, { model: m.value })) } })))
      },
    },
    { key: "y", label: b.ask === "allow" ? "ask before acting" : "allow without asking", run: () => void did(data.retarget(w, b.agent_id, { ask: b.ask === "allow" ? "ask" : "allow" })) },
    {
      key: "E", label: "persona…", run: () => {
        const p = b.persona
        const items: { label: string; run: () => void }[] = [
          { label: p ? "draw a new one (reroll)" : "make one", run: () => void did(data.persona(w, b.agent_id, !!p)) },
          ...(p ? [
            { label: "edit the voice", run: () => ask(`${b.name}'s voice`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { voice: s.trim() })) }, { text: p.voice }) },
            { label: "edit the backstory", run: () => ask(`${b.name}'s backstory`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { backstory: s.trim() })) }, { text: p.backstory }) },
            ...(["desk_object", "hobby", "catchphrase", "pet_peeve"] as const).map((k) => ({ label: `edit ${k.replace("_", " ")}`, run: () => ask(`${b.name}'s ${k.replace("_", " ")}`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { quirks: { [k]: s.trim() } })) }, { text: p.quirks[k] }) })),
          ] : []),
        ]
        find(`${b.name.toUpperCase()}'S PERSONA`, items.map((i) => ({ segs: [plain(i.label)], text: i.label, run: () => { picker = null; i.run() } })))
      },
    },
    { key: "C", label: "clear context (fresh next time)", run: () => ask2(`clear ${b.name}'s context — their session ends, they start fresh when next needed`, () => did(data.clearContext(w, b.agent_id, b.name))) },
    { key: "-", label: "let go", run: () => ask2(`let ${b.name} go from ${wsName()} (the agent itself stays)`, () => did(data.unseat(b.seat_id, b.name))) },
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
const cols = () => process.stdout.columns ?? 80

/**
 * Threads whose card shows the conversation instead of the running coworkers' activity timeline
 * (`tui/timeline.ts`, from the thread view's `activity`) — `c` flips, ⏎ steps into the session itself.
 */
const talkView = new Set<number>()
/** playerctl, polled every ~2s: feeds the wide room's stereo marquee + dance trigger */
function pollPlayer() {
  const rm = room()
  if (!(rm instanceof WideRoom)) return
  try {
    const r = Bun.spawnSync(["playerctl", "metadata", "--format", "{{ title }}|{{ artist }}|{{ bpm }}"])
    rm.setPlayer(r.exitCode === 0 ? parseNowPlaying(r.stdout.toString()) : null)
  } catch {
    rm.setPlayer(null)
  }
}
/** refresh a thread's close look; true when its activity feed moved */
async function pollActivity(tid: number) {
  const was = threads.get(tid)?.activity?.at(-1)
  await loadThread(tid)
  const now = threads.get(tid)?.activity?.at(-1)
  return was?.at !== now?.at || was?.summary !== now?.summary
}
/** the actions a running thread's card adds: step into the session, flip activity and conversation */
function liveActions(tid: number): Action[] {
  if (!threadOf(tid)?.live) return []
  return [
    { key: "enter", label: "step into their session", run: () => void zoomInto(tid) },
    { key: "c", label: talkView.has(tid) ? "their activity" : "the conversation", run: () => { if (!talkView.delete(tid)) talkView.add(tid); draw() } },
  ]
}
/** an author's colour: you in pink, the server dim, a coworker in their archetype's */
const authorColor = (author: string) =>
  author === OPERATOR ? ROLE.attention : author === "tlon" ? ROLE.inactive : shirtOf(all.bench.find((b) => b.name === author)?.archetype)
const STAGE_RING = ["intent", "spec", "plan", "build", "verify", "review", "merged"]

/** the detail pane's lines under its title, with a one-line foot */
const paneRows = () => (g ? Math.max(1, (process.stdout.rows ?? 40) - (g.row + g.rows + 2) - 2) : DETAIL - 2)
/** the detail pane's text width: the terminal's, less the actions column when there is room for it */
const paneW = () => (cols() >= 80 ? cols() - ACTIONS_W - 1 : cols())
/** a thread's rows for a card; `above`: the card's own rows over them, so the tail still ends in view */
function threadRows(th: Thread | undefined, tid: number, above = 0): Row[] {
  const v = threads.get(tid), out: Row[] = []
  out.push({ segs: [key(`#${tid} `), plain(th?.title ?? "")] })
  // a workline's stages as a track (done ones lit, the current one a chip); a plain thread's lead and state
  const cur = th?.stage ? STAGE_RING.indexOf(th.stage) : -1
  out.push({
    segs: [
      ...(th?.stage
        ? STAGE_RING.flatMap((st, i): Seg[] => [...(i ? [dim(" ▸ ")] : []), i === cur ? { s: ` ${st} `, fg: ROLE.ground, bg: th.awaiting ? ROLE.attention : ROLE.key, bold: true } : { s: st, fg: i < cur ? ROLE.live : ROLE.inactive }])
        : [dim("thread")]),
      ...(th?.lead ? [dim("  · "), { s: th.lead, fg: authorColor(th.lead), bold: true }] : []),
      ...(th?.live ? [{ s: "  ● running", fg: ROLE.live }] : []),
    ],
  })
  // a board card's state, and the one thing that moves it
  const st = th && !th.duty && (th.stage || (th.lead && !th.standing)) ? cardState(view(), th, boardCtx()) : null
  if (th && st) { const n = nextStep(th, st); out.push({ segs: [stateSeg(st), { s: st.why, fg: st.kind === "needs" ? ROLE.attention : ROLE.prose }, dim("  → "), key(`${n.key} `), plain(n.label)] }) }
  if (th?.prompt) {
    out.push({ segs: [pink("asks: "), plain(th.prompt.summary)] })
    th.prompt.options?.forEach((o, i) => out.push({ segs: [key(` ${i + 1} `), plain(o.label)], open: () => did(data.post(tid, o.key)) }))
  } else if (th?.awaiting && !st) out.push({ segs: [pink(`awaits ${th.awaiting}${th.stage ? " — A approves" : ""}`)] })
  // a running thread's activity, every event the server keeps: the pane opens on the newest and
  // scrolls back (pgup/pgdn, the wheel) — unless you flipped to the conversation
  if (th?.live && !talkView.has(tid)) {
    const feed = v?.activity ?? [], live = new Set(all.roster.filter((r) => r.thread_id === tid && r.thinking).map((r) => r.agent))
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
/** a card state's glyph: ▶ at a desk, ⏸ parked, ○ idle, ⚑ needs you */
const stateSeg = (st: CardState): Seg => ({ s: `${STATE_GLYPH[st.kind]} `, fg: st.kind === "running" ? ROLE.live : st.kind === "needs" ? ROLE.attention : ROLE.inactive, bold: true })
/** the one thing to do about a board card, by where it stands */
function nextStep(th: Thread, st: CardState): { key: string; label: string } {
  const options = th.prompt?.options?.length ?? 0
  if (st.kind === "needs" && options) return { key: options > 1 ? `1–${Math.min(9, options)}` : "1", label: "answer it" }
  if (st.kind === "needs" && th.awaiting && th.stage) return { key: "A", label: `approve: ${th.awaiting}` }
  if (st.atCap) return { key: "S", label: "raise the cap in settings" }
  return { key: "v", label: "open the reader" }
}
const ago = (at: string) => {
  const s = Math.max(0, (Date.now() - new Date(at).getTime()) / 1000)
  return s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`
}
const stamp = (at: string) => {
  const d = new Date(at), p = (n: number) => String(n).padStart(2, "0")
  return `${d.toDateString().slice(4, 10)} ${p(d.getHours())}:${p(d.getMinutes())}`
}
const runGlyph = (r: { status: string }): Seg => (r.status === "ok" ? { s: "✓", fg: ROLE.live } : r.status === "failed" ? { s: "✗", fg: ROLE.alarm } : { s: "…", fg: ROLE.key })
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
  if (ws === null) return
  const w = ws, bench = view().bench
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
      if (!when) { status = "a schedule needs a when"; return draw() }
      const attrs = { body: body.trim(), standing: standing as boolean, agent: kind === "agent" ? (agent as string | null) : null, ...when }
      void did(edit ? data.schedulePatch(edit.id, attrs) : data.scheduleNew(w, { kind: kind as data.ScheduleKind, ...attrs })).then(loadCard).then(draw)
    }, { text: edit ? showWhen(edit) : "" })
  }, { multiline: true, text: edit?.body, cycles })
}
/** a new routine (title, then how often) */
function newRoutine() {
  if (ws === null) return
  const w = ws
  ask("routine — what", (title) => {
    if (!title.trim()) return
    ask("every — a cron (0 9 * * *) or @daily / @weekly", (every) => {
      if (every.trim()) void did(data.routineNew(w, title.trim(), every.trim())).then(loadCard).then(draw)
    })
  })
}
function newQuest() {
  if (ws === null) return
  const w = ws
  ask("quest — what", (title) => { if (title.trim()) void did(data.questNew(w, title.trim())).then(loadCard).then(draw) })
}
const KIND: Record<string, string> = { message: "said", fact: "learned", issue: "raised", question: "asked", check_failed: "check failed", check_passed: "check passed", work_landed: "landed", stage_advanced: "advanced", handoff_opened: "handed off" }

const back1: Action = { key: "esc", label: "back", run: () => { back(); roomChanged = true; draw() } }
const pick = <T,>(xs: T[], i: number) => (i >= 0 ? xs[i] : undefined)

/** the card the pane shows: its title, its rows (the left, j/k + enter when any open), its actions (the right, by key) */
function detail(): { title: string; rows: Row[]; actions: Action[]; tint?: string } {
  const a = view(), w = ws
  switch (mode.kind) {
    case "home": {
      const waiting = a.threads.filter(needsYou)
      const actions: Action[] = [
        { key: "/", label: "find anything", run: () => void finder() }, { key: "i", label: "inbox — everywhere", run: inbox },
        { key: "n", label: "new thread", run: newThread }, { key: "N", label: "new ticket", run: newTicket },
        { key: "c", label: "crew", run: () => open({ kind: "crew" }) }, { key: "t", label: "tickets & worklines", run: () => open({ kind: "column", col: 0 }) },
        { key: "w", label: "in-tray", run: () => open({ kind: "tray" }) }, { key: "!", label: "triage", run: () => open({ kind: "triage" }) },
        { key: "a", label: "calendar", run: () => open({ kind: "calendar" }) }, { key: "o", label: "notes", run: () => open({ kind: "notes" }) },
        { key: "b", label: "memory", run: () => open({ kind: "memory" }) }, { key: "H", label: "the rack (health)", run: () => open({ kind: "health" }) },
        ...(all.life?.[String(w)] ? [{ key: "L", label: "life", run: () => open({ kind: "life" }) }] : []),
        ...(flagOn(all, "build_mode") ? [{ key: "B", label: "build mode", run: () => open({ kind: "build" }) }] : []),
        { key: "f", label: "filing cabinet", run: () => open({ kind: "archive" }) }, { key: "W", label: "workspaces", run: () => open({ kind: "boss" }) },
        { key: "q", label: "quit", run: quit },
      ]
      if (!waiting.length) return { title: "HOME", rows: [{ segs: [dim("nothing waits on you. click someone — or Nina, or Argos — a sticky or the crew board;")] }, { segs: [dim("tab walks the crew, [ ] the workspaces.")] }], actions }
      return { title: `WAITING ON YOU · ${waiting.length}`, rows: waiting.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), pink(`  ${t.prompt?.summary ?? `awaits ${t.awaiting}`}`)], open: () => openReader(t.id, false) })), actions }
    }
    case "crew": {
      // tabs: the day crew, the night crew, everyone; the crew on shift has the live status
      const seats = (all.shifts ?? []).filter((x) => x.workspace_id === ws)
      const on = all.workspaces.find((w) => w.id === ws)?.shift ?? "day", other = on === "day" ? "night" : "day"
      const live = crewOf(a)
      const inTab = (name: string) => crewTab === "all" || seats.find((x) => x.name === name)?.crew === crewTab
      const crew = [...live, ...seats.filter((x) => !live.some((c) => c.name === x.name)).map((x) => ({ name: x.name, archetype: x.archetype, status: "off", thread: null, title: "", manager: false, lead: false }))].filter((c) => inTab(c.name))
      const shiftOf = (name: string) => seats.find((x) => x.name === name)?.crew
      const tabs: Seg[] = (["day", "night", "all"] as const).flatMap((t) => [t === crewTab ? { s: ` ${TAB_LABEL[t]} `, fg: ROLE.ground, bg: ROLE.key, bold: true } : dim(` ${TAB_LABEL[t]} `), plain(" ")])
      const rows: Row[] = [{ segs: [...tabs, dim(`   the ${on} shift is on`)] }]
      for (const g of arrange(crew as any, crewSort.cmp, crewGroup)) {
        if (g.label !== null) rows.push({ segs: [key(`${g.label} · ${g.items.length}`)] })
        for (const c of g.items as any[]) {
          const b = a.bench.find((x) => x.name === c.name), arch = a.archetypes.find((x) => x.name === c.archetype)
          const model = b?.model ? b.model.model : arch?.model?.split("/").pop() ?? ""
          const off = c.status === "off", shift = shiftOf(c.name)
          rows.push({
            segs: [{ s: off ? "◌ " : c.status === "working" ? "● " : c.status === "waiting" ? "! " : "○ ", fg: off ? ROLE.inactive : c.status === "working" ? ROLE.live : c.status === "waiting" ? ROLE.attention : ROLE.inactive },
              { s: c.name.padEnd(10), fg: off ? ROLE.inactive : shirtOf(c.archetype) }, dim(`${c.manager ? "manager" : c.archetype ?? "?"}${c.lead ? " · lead" : ""}`.padEnd(18)), key(model.padEnd(16)),
              dim((shift === "night" ? "☾ nights" : shift === "day" ? "☼ days" : "both").padEnd(10)),
              dim(off ? "off shift" : c.thread !== null ? `#${c.thread} ${c.title}` : "on the bench")],
            open: () => open({ kind: "person", name: c.name }), ref: c.name,
          })
        }
      }
      const chosen = a.bench.find((x) => x.name === rows[sel]?.ref), seat = seats.find((x) => x.name === rows[sel]?.ref)
      const put = (k: string, crewTo: "day" | "night" | "all"): Action => ({ key: k, label: crewTo === "all" ? "on both" : `on ${crewTo === "day" ? "days" : "nights"}`, run: () => { if (seat) void did(data.seatShift(seat.seat_id, seat.name, crewTo)) } })
      return {
        title: `CREW · ${crew.length} · ${TAB_LABEL[crewTab]} · by ${crewGroup ? `${crewGroup.name}, ` : ""}${crewSort.name}`,
        rows,
        actions: [{ key: "v", label: `tab: ${TAB_LABEL[next(CREW_TABS, crewTab)]}`, run: () => { crewTab = next(CREW_TABS, crewTab); sel = 0; draw() } },
          put("d", "day"), put("n", "night"), put("b", "all"),
          { key: "S", label: `start the ${other} shift`, run: () => { if (ws !== null) void did(data.shiftSwitch(ws, other)) } },
          { key: "+", label: "hire", run: hire },
          { key: "s", label: `sort: ${crewSort.name} → ${next(CREW_SORTS, crewSort).name}`, run: () => resort(() => { crewSort = next(CREW_SORTS, crewSort) }) },
          { key: "g", label: `group: ${crewGroup?.name ?? "none"} → ${next(CREW_GROUP_MODES, crewGroup)?.name ?? "none"}`, run: () => resort(() => { crewGroup = next(CREW_GROUP_MODES, crewGroup) }) },
          ...seatActions(chosen), back1],
      }
    }
    case "person": {
      const name = mode.name
      const c = crewOf(a).find((x) => x.name === name), b = a.bench.find((x) => x.name === name)
      if (!c) return { title: name.toUpperCase(), rows: [{ segs: [dim("not in this office any more")] }], actions: [back1] }
      const model = b?.model ? `${b.model.provider}/${b.model.model}` : `${a.archetypes.find((x) => x.name === c.archetype)?.model ?? "?"} (archetype's)`
      const where = c.status === "working" ? "mid-turn" : a.roster.some((r) => r.agent === name && r.warm) ? "on call" : c.status === "waiting" ? "waiting on you" : "in the lounge"
      // a pill for where they are, and what they're at mid-turn (the thought bubble's kind)
      const doing = a.roster.find((r) => r.agent === name && r.thinking)?.doing
      const pill = c.status === "working" ? ROLE.live : c.status === "waiting" ? ROLE.attention : where === "on call" ? ROLE.key : ROLE.inactive
      const head: Row = {
        segs: [{ s: ` ${c.name} `, fg: ROLE.ground, bg: shirtOf(c.archetype), bold: true }, plain(" "), { s: ` ${where}${doing ? ` · ${doing}` : ""} `, fg: ROLE.ground, bg: pill },
          dim(`  ${c.manager ? "manager" : c.archetype ?? ""}${c.lead ? " · lead" : ""} · ${model} · ${b?.ask ?? "ask (archetype's)"}`)],
      }
      const soul = soulFor(name)
      const soulRows: Row[] = soul ? [{ segs: [dim("soul")] }, ...soulLines(soul).flatMap(({ head: h, text }) => [...(h ? [{ segs: [key(h)] }] : []), ...text.split("\n").map((l) => ({ segs: [plain(l)] }))])] : []
      const rows: Row[] = [...(c.thread === null ? [head, { segs: [dim("on the bench")] }] : [head, ...threadRows(threadOf(c.thread), c.thread, 1)]), ...soulRows]
      for (const l of personaLines(b?.persona, Math.max(20, cols() - 40))) rows.push({ segs: [dim(l)] })
      return { title: name.toUpperCase(), rows, tint: shirtOf(c.archetype), actions: [{ key: "m", label: "talk", run: () => talk(name) }, ...(c.thread === null ? [] : [...liveActions(c.thread), ...threadActions(c.thread)]), ...seatActions(b), { key: "l", label: "look", run: () => open({ kind: "look", name }) }, back1] }
    }
    case "thread": {
      const tid = mode.tid
      const th = threadOf(tid)
      return { title: `THREAD #${tid}${th?.stage ? ` · workline ${th.stage}` : ""}`, rows: threadRows(th, tid), tint: th?.awaiting || th?.prompt ? ROLE.attention : th?.lead ? authorColor(th.lead) : ROLE.key, actions: [...liveActions(tid), ...threadActions(tid), back1] }
    }
    case "column": {
      const col = boardColumns(a, boardCtx())[mode.col]!, items = arrange(col.items, colSort.cmp, null)[0]!.items
      const it = pick(items, sel)
      const reorder = (dir: "up" | "down"): Action => ({ key: dir === "up" ? "K" : "J", label: `move ${dir}`, run: () => { if (it?.act.kind === "ticket") void did(data.ticketReorder(it.act.id, dir)).then(() => { sel = Math.max(0, Math.min(sel + (dir === "up" ? -1 : 1), items.length - 1)); draw() }) } })
      return {
        title: `${col.name} · ${items.length}${colSort.name === "board" ? "" : ` · by ${colSort.name}`}`,
        rows: items.map((x) => {
          const blocked = x.act.kind === "ticket" && (tickets.find((t) => t.id === (x.act as { id: number }).id)?.blocked_by.length ?? 0) > 0
          return {
            segs: [...(x.state ? [stateSeg(x.state)] : []), key(x.act.kind === "ticket" || x.act.kind === "epic" ? `#${x.act.id} ` : x.act.kind === "thread" ? `#${x.act.tid} ` : ""), plain(x.title), dim(`  ${x.stage}${x.who ? ` · ${x.who}` : ""}`),
              ...(x.state ? [{ s: `  ${x.state.why}`, fg: x.state.kind === "needs" ? ROLE.attention : ROLE.inactive }] : x.asks ? [pink("  waiting on you")] : []), ...(blocked ? [pink("  ⊘ blocked")] : [])],
            open: () => act(x.act), ref: JSON.stringify(x.act),
          }
        }),
        actions: [
          ...(mode.col === 0 ? [{ key: "n", label: "new ticket", run: newTicket }, ...(colSort.name === "board" ? [reorder("up"), reorder("down")] : [])] : []),
          { key: "s", label: `sort: ${colSort.name} → ${next(COL_SORTS, colSort).name}`, run: () => resort(() => { colSort = next(COL_SORTS, colSort) }) },
          { key: "right", label: "next column (← →)", run: () => open({ kind: "column", col: ((mode as { col: number }).col + 1) % COLS.length }) },
          back1,
        ],
      }
    }
    case "epic": {
      const id = mode.id, ep = a.tickets.find((t) => t.id === id)
      if (!ep) return { title: `EPIC #${id}`, rows: [{ segs: [dim("finished or gone")] }], actions: [back1] }
      const kids = epicChildren(a, id)
      return {
        title: `EPIC #${id} · ${ep.done ?? 0}/${ep.total ?? 0}`,
        rows: [{ segs: [plain(ep.title)] }, { segs: [dim(`${ep.priority} priority${ep.next ? ` · next #${ep.next.id} ${ep.next.title}` : ""}`)] },
          ...kids.map((k) => ({ segs: [key(`#${k.id} `), plain(k.title), dim(`  ${k.routed ? "with the manager" : "ticket"}`)], open: () => act({ kind: "ticket", id: k.id }), ref: JSON.stringify({ kind: "ticket", id: k.id }) }))],
        actions: [back1],
      }
    }
    case "ticket": {
      const id = mode.id
      const tk = a.tickets.find((t) => t.id === id), full = tickets.find((t) => t.id === id)
      if (!tk) return { title: `TICKET #${id}`, rows: [{ segs: [dim("started or gone")] }], actions: [back1] }
      const rows: Row[] = [{ segs: [plain(tk.title)] }, { segs: [dim(`${tk.priority} priority${tk.routed ? " · with the manager to staff" : ""}`)] }]
      const parent = tk.epic_id != null ? a.tickets.find((t) => t.id === tk.epic_id) : undefined
      if (parent) rows.push({ segs: [dim("epic "), key(`#${parent.id} `), plain(parent.title)] })
      for (const by of full?.blocked_by ?? []) rows.push({ segs: [pink("⊘ blocked by "), key(`#${by} `), plain(tickets.find((t) => t.id === by)?.title ?? "")] })
      if (full?.body) for (const l of wrap(full.body, cols() - 40)) rows.push({ segs: [dim(l)] })
      return {
        title: `TICKET #${id}`, rows,
        actions: [
          { key: "S", label: "start it with the lead", run: () => void did(data.ticketStart(id)) },
          { key: "s", label: "send to the manager to staff", run: () => void did(data.ticketRoute(id)) },
          { key: "e", label: "edit the title", run: () => ask(`ticket #${id} title`, (s) => { if (s.trim()) did(data.ticketPatch(id, { title: s.trim() })) }, { text: tk.title }) },
          {
            key: "b", label: "blocked by…", run: () => {
              const others = tickets.filter((t) => t.id !== id && t.status !== "done")
              find(`#${id} IS BLOCKED BY`, others.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), dim(`  ${t.status}`)], text: `#${t.id} ${t.title}`, run: () => { picker = null; void did(data.ticketBlock(id, t.id)) } })))
            },
          },
          ...(full?.blocked_by.length ? [{ key: "u", label: "unblock", run: () => { for (const by of full.blocked_by) void did(data.ticketUnblock(id, by)) } }] : []),
          { key: "K", label: "move up", run: () => void did(data.ticketReorder(id, "up")) }, { key: "J", label: "move down", run: () => void did(data.ticketReorder(id, "down")) },
          { key: "d", label: "delete", run: () => ask2(`delete ticket #${id}`, () => { back(); void did(data.ticketDelete(id)) }) },
          back1,
        ],
      }
    }
    case "calendar": {
      const now = new Date(), first = new Date(now.getFullYear(), now.getMonth(), 1).getDay(), days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
      const booked = new Set((cal ?? []).filter((s) => s.enabled).flatMap((s) => s.days))
      const rows: Row[] = [{ segs: [dim("  Su  Mo  Tu  We  Th  Fr  Sa")] }]
      let week: Seg[] = [plain("    ".repeat(first))]
      for (let d = 1; d <= days; d++) {
        const cell = String(d).padStart(3) + (booked.has(d) ? "•" : " ")
        week.push(d === now.getDate() ? { s: cell, fg: ROLE.attention, bold: true } : booked.has(d) ? key(cell) : d < now.getDate() ? dim(cell) : plain(cell))
        if ((first + d) % 7 === 0 || d === days) { rows.push({ segs: week }); week = [] }
      }
      if (!cal) rows.push({ segs: [dim("reading the schedule…")] })
      else if (!cal.length) rows.push({ segs: [dim("nothing scheduled yet")] })
      else {
        rows.push({ segs: [key(`SCHEDULED · ${cal.length}`)] })
        for (const s of cal) rows.push({ segs: scheduleSegs(s), open: () => open({ kind: "runs", id: s.id }), ref: s })
      }
      const s = rows[sel]?.ref as data.Schedule | undefined
      return {
        title: now.toLocaleString("en", { month: "long", year: "numeric" }).toUpperCase(), rows,
        actions: [
          { key: "n", label: "schedule something", run: () => newSchedule() },
          ...(s ? [
            { key: "e", label: "edit it", run: () => newSchedule(s) },
            { key: "space", label: s.enabled ? "pause it" : "resume it", run: () => void did(data.schedulePatch(s.id, { enabled: !s.enabled })).then(loadCard).then(draw) },
            { key: "r", label: "run it now", run: () => void did(data.scheduleRun(s.id)).then(loadCard).then(draw) },
            { key: "d", label: "delete it", run: () => ask2(`remove "${s.title}" and its runs`, () => void did(data.scheduleDelete(s.id)).then(loadCard).then(draw)) },
          ] : []),
          back1,
        ],
      }
    }
    case "life": {
      const s = lifeCard
      const rows: Row[] = s ? lifeRows(s).map((r) => ({
        segs: [plain(r.text)],
        open: () => void did(r.kind === "routine" ? data.routineDone(r.id, r.title) : data.questDone(r.id, r.title)).then(loadCard).then(draw),
      })) : [{ segs: [dim("reading the day…")] }]
      if (s && !rows.length) rows.push({ segs: [dim("nothing due, no open quests")] })
      return {
        title: s ? `LIFE · lv ${s.level} · ${s.xp} xp` : "LIFE", rows,
        actions: [{ key: "r", label: "new routine", run: newRoutine }, { key: "q", label: "new quest", run: newQuest }, back1],
      }
    }
    case "runs": {
      const id = mode.id, s = cal?.find((x) => x.id === id)
      const rows: Row[] = board.map((r) => ({
        segs: [runGlyph(r), dim(` ${stamp(r.started_at)} `), plain(r.status.padEnd(8)), dim(r.exit === null ? "" : `exit ${r.exit}  `), r.thread_id ? key(`→ #${r.thread_id}  `) : dim(""), dim((r.output ?? "").replace(/\s+/g, " ").slice(0, 80))],
        open: () => (r.thread_id && !r.output ? openReader(r.thread_id, false) : open({ kind: "run", id, run: r.id })),
        ref: r,
      }))
      return {
        title: `RUNS · ${s?.title ?? ""}`, rows: rows.length ? rows : [{ segs: [dim("it hasn't run yet")] }],
        actions: [{ key: "r", label: "run it now", run: () => void did(data.scheduleRun(id)).then(loadCard).then(draw) }, { key: "esc", label: "the calendar", run: () => open({ kind: "calendar" }) }],
      }
    }
    case "run": {
      const { id, run } = mode
      const r = board.find((x) => x.id === run)
      const up: Action = { key: "esc", label: "the runs", run: () => open({ kind: "runs", id }) }
      if (!r) return { title: "RUN", rows: [{ segs: [dim("gone")] }], actions: [up] }
      const rows: Row[] = [{ segs: [runGlyph(r), dim(` started ${stamp(r.started_at)}${r.finished_at ? `, finished ${stamp(r.finished_at)}` : ", still running"}`), ...(r.thread_id ? [key(`  → #${r.thread_id}`)] : [])] }]
      for (const l of wrap(r.output ?? "(no output)", cols() - 40)) rows.push({ segs: [plain(l)] })
      return { title: `RUN #${r.id} · ${r.status}${r.exit === null ? "" : ` · exit ${r.exit}`}`, rows, actions: [...(r.thread_id ? [{ key: "t", label: "read its thread", run: () => openReader(r.thread_id!, false) }] : []), up] }
    }
    case "archive": {
      if (!archived) return { title: "FILING CABINET", rows: [{ segs: [dim("opening the drawers…")] }], actions: [back1] }
      const day = (s: string | null) => (s ? s.slice(0, 10) : "")
      const rows: Row[] = [{ segs: [key(`TICKETS DONE · ${archived.tickets.length}`)] }]
      for (const t of archived.tickets) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${day(t.closed_at)}`)] })
      rows.push({ segs: [key(`THREADS CLOSED · ${archived.threads.length}`)] })
      for (const t of archived.threads) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${t.stage ?? ""} ${day(t.at)}`)], open: () => openReader(t.id, false) })
      return { title: "FILING CABINET", rows, actions: [back1] }
    }
    case "notes": {
      const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const rows: Row[] = a.notes.map((n) => ({ segs: [who(n.author), plain(n.body.replace(/\s+/g, " "))] }))
      // the crew's chatter, apart from the notes they work from (their suggestions go in the box)
      if (cork.length) rows.push({ segs: [key(`CORKBOARD · ${cork.length} — the crew's notes to each other`)] }, ...cork.map((n): Row => ({ segs: [dim(`${n.kind.padEnd(10)} `), who(n.author), plain(n.body), dim(n.re ? `  (re #${n.re})` : "")], ref: n })))
      return { title: `NOTES · ${a.notes.length}`, rows, actions: [{ key: "n", label: "pin a note", run: newNote }, back1] }
    }
    case "tray": {
      const rows = arrange(feed, traySort.cmp, null)[0]!.items.map((x): Row => ({
        segs: [dim(ago(x.at).padStart(4) + " "), x.thread_id ? key(`#${x.thread_id} `) : dim(""), { s: `${x.who ?? ""} ${KIND[x.kind] ?? x.kind.replace(/_/g, " ")} `, fg: x.kind === "issue" || x.kind === "check_failed" ? ROLE.alarm : x.kind === "question" ? ROLE.attention : ROLE.inactive }, plain(x.text.replace(/\s+/g, " "))],
        open: x.thread_id ? () => openReader(x.thread_id!, false) : undefined, ref: `${x.at}${x.kind}${x.text}`,
      }))
      return {
        title: `IN-TRAY · ${wsName()}${traySort.name === "newest" ? "" : ` · by ${traySort.name}`}`, rows: rows.length ? rows : [{ segs: [dim("nothing yet")] }],
        actions: [{ key: "s", label: `sort: ${traySort.name} → ${next(TRAY_SORTS, traySort).name}`, run: () => resort(() => { traySort = next(TRAY_SORTS, traySort) }) }, back1],
      }
    }
    case "triage": {
      if (!stuck) return { title: "TRIAGE", rows: [{ segs: [dim("looking…")] }], actions: [back1] }
      const rows: Row[] = []
      const section = (name: string, c: data.Capped<data.Stuck>) => {
        if (!c.shown.length) return
        rows.push({ segs: [key(name)] })
        for (const s of c.shown) rows.push({ segs: [key(`  #${s.thread_id} `), plain(s.title), pink(`  ${s.text}`)], open: () => openReader(s.thread_id, false) })
        if (c.more) rows.push({ segs: [dim(`  +${c.more} more`)] })
      }
      section("BLOCKERS — open issues", stuck.blockers); section("FAILED CHECKS", stuck.failed_checks); section("NOBODY LEADS", stuck.unled)
      return { title: `TRIAGE · ${stuck.count} known problems · the sheriff's`, rows: rows.length ? rows : [{ segs: [dim("nothing is stuck. the beacon is dark.")] }], actions: [back1] }
    }
    case "health": {
      if (!rack) return { title: "THE RACK", rows: [{ segs: [dim("probing…")] }], actions: [back1] }
      const ok = (b: boolean, s: string): Row => ({ segs: [{ s: b ? "● " : "✕ ", fg: b ? ROLE.live : ROLE.alarm }, plain(s)] })
      const up = rack.up_s < 3600 ? `${Math.floor(rack.up_s / 60)}m` : rack.up_s < 86400 ? `${Math.floor(rack.up_s / 3600)}h` : `${Math.floor(rack.up_s / 86400)}d`
      const rows: Row[] = [
        ...rack.problems.map((p) => ({ segs: [pink("! "), plain(p)] })),
        ok(true, `tlon ${rack.version}, up ${up}`), ok(rack.db, "the database answers"), ok(rack.jobs, rack.jobs ? "the job queue runs (staffing, sweeps, schedules)" : "no job queue on this node"),
        ok(rack.failed_jobs === 0, `${rack.failed_jobs} failed job(s) today`), ok(rack.tmux, "tmux is there for the coworkers"),
        { segs: [dim(`disk ${rack.disk_pct ?? "?"}% · memory ${rack.mem_pct ?? "?"}% · load ${rack.load ?? "?"}`)] },
      ]
      return { title: `THE RACK · ${rack.state === "ok" ? "all green" : "needs a look"}`, rows, actions: [back1] }
    }
    case "memory": {
      if (!shelf) return { title: "MEMORY", rows: [{ segs: [dim("taking the books down…")] }], actions: [back1] }
      const rows: Row[] = [{ segs: [dim(`${shelf.coverage.facts} facts, ${shelf.coverage.embedded} embedded · pinned ${shelf.coverage.pinned_count} (~${shelf.coverage.pinned_tokens} of ${shelf.coverage.budget} tokens)`)] }]
      rows.push({ segs: [key(`HABITS TO REVIEW · ${shelf.habits.length}`)] })
      for (const h of shelf.habits) rows.push({ segs: [dim(`  ${h.by ?? "?"}: `), plain(h.text)], open: () => void 0, ref: { habit: h } })
      rows.push({ segs: [key(`PINNED — every session loads these · ${shelf.pinned.length}`)] })
      for (const f of shelf.pinned) rows.push({ segs: [dim(`  ${f.id} `), plain(f.text.replace(/\s+/g, " "))], open: () => void 0, ref: { fact: f } })
      const at = rows[sel]?.ref as { habit?: data.Memory["habits"][number]; fact?: data.Memory["pinned"][number] } | undefined
      const reload = () => void loadCard().then(draw)
      return {
        title: "MEMORY", rows,
        actions: [
          ...(at?.habit ? [{ key: "a", label: "approve the habit", run: () => void did(data.habit(at.habit!.id, "approve")).then(reload) }, { key: "r", label: "reject the habit", run: () => void did(data.habit(at.habit!.id, "reject")).then(reload) }] : []),
          ...(at?.fact ? [{ key: "d", label: "forget the fact", run: () => ask2(`forget "${at.fact!.text.slice(0, 50)}"`, () => void did(data.forget(at.fact!.id)).then(reload)) }] : []),
          back1,
        ],
      }
    }
    case "build": {
      if (!build) build = startBuild(loadHome())
      const b = build
      const mutate = (f: (b: Build) => Build): (() => void) => () => {
        build = applyBuild(build!, f)
        draw()
      }
      const rows: Row[] = [{ segs: [dim("the home is drawn above")] }]
      return {
        title: `BUILD MODE${b.carrying ? ` · carrying ${b.carrying.kind}` : ""}${b.refused ? " · refused — overlap or it would split the floor" : ""}`,
        rows,
        actions: [
          { key: "up", label: "move", run: mutate((x) => move(x, 0, -1)) },
          { key: "down", label: "move", run: mutate((x) => move(x, 0, 1)) },
          { key: "left", label: "move", run: mutate((x) => move(x, -1, 0)) },
          { key: "right", label: "move", run: mutate((x) => move(x, 1, 0)) },
          { key: "enter", label: b.carrying ? "drop" : "pick up", run: mutate((x) => (x.carrying ? drop(x) : pickUp(x))) },
          { key: "n", label: "new tile (cycles the kind)", run: mutate((x) => place(x)) },
          { key: "x", label: "remove", run: mutate((x) => remove(x)) },
          { key: "r", label: "rotate", run: mutate((x) => rotate(x)) },
          { key: "u", label: "undo", run: mutate((x) => undo(x)) },
          { key: "esc", label: "leave", run: () => { back(true); roomChanged = true; draw() } },
        ],
      }
    }
    case "boss": {
      const rows: Row[] = [{ segs: [plain(all.awaiting ? `${all.awaiting} thread(s) wait on you across the office` : "nothing waits on you")] }]
      for (const x of all.workspaces) {
        const n = all.threads.filter((t) => t.workspace_id === x.id && needsYou(t)).length, s = all.triage[String(x.id)] ?? 0
        rows.push({ segs: [key(x.id === ws ? "▸ " : "  "), plain(x.name.padEnd(16)), n ? pink(`${n} waiting  `) : dim(""), s ? dim(`${s} issues`) : dim("")], open: () => goWs(x.id) })
      }
      return {
        title: "WORKSPACES", rows,
        actions: [
          {
            key: "n", label: "new workspace", run: () => {
              const tpl = ["code", "life", "blank"].map((t) => ({ label: t, value: t }))
              ask("new workspace — its name", (s, [t]) => { if (s.trim()) did(data.workspaceNew(s.trim(), t as string)) }, { cycles: [{ name: "from", values: tpl, i: 0 }] })
            },
          },
          { key: "e", label: "this one's settings", run: () => open({ kind: "card" }) },
          { key: "S", label: "the running system", run: () => open({ kind: "settings" }) },
          ...(w === null ? [] : [{ key: "d", label: "close this one", run: () => ask2(`close ${wsName()} (its threads move to another workspace)`, () => void did(data.workspaceDelete(w))) }]),
          { key: "+", label: "hire", run: hire },
          back1,
        ],
      }
    }
    case "card": {
      if (!card || w === null) return { title: "SETTINGS", rows: [{ segs: [dim("reading…")] }], actions: [back1] }
      const c = card, ring = (xs: string[], x: string) => xs[(xs.indexOf(x) + 1) % xs.length]!
      const reload = () => void loadCard().then(draw)
      const rows: Row[] = [
        { segs: [dim("type  "), plain(c.type), dim("   scope  "), plain(c.scope), dim("   icon  "), plain(c.icon ?? "—")] },
        { segs: [key(`REPOS · ${c.repos.length}`)] },
        ...c.repos.map((r): Row => ({ segs: [plain(`  ${r.path}`), dim(r.remote ? `  ${r.remote}` : "")], open: () => void 0, ref: r })),
      ]
      const repo = rows[sel]?.ref as data.WorkspaceCard["repos"][number] | undefined
      return {
        title: `${c.name.toUpperCase()} · SETTINGS`, rows,
        actions: [
          { key: "T", label: `type: ${c.type} → next`, run: () => void did(data.workspaceEdit(w, { type: ring(["code", "life", "blank"], c.type) })).then(reload) },
          { key: "s", label: `scope: ${c.scope} → next`, run: () => void did(data.workspaceEdit(w, { scope: ring(["project", "machine"], c.scope) })).then(reload) },
          { key: "I", label: "icon", run: () => ask("icon", (s) => void did(data.workspaceEdit(w, { icon: s.trim() })).then(reload), { text: c.icon ?? "" }) },
          { key: "+", label: "add a repo", run: () => ask("add a repo — its path", (s) => { if (s.trim()) void did(data.repoAdd(w, s.trim())).then(reload) }) },
          ...(repo ? [{ key: "-", label: `remove ${repo.path.split("/").pop()}`, run: () => ask2(`remove ${repo.path} from ${c.name}`, () => void did(data.repoRemove(repo.id)).then(reload)) }] : []),
          back1,
        ],
      }
    }
    case "settings": {
      if (!settings) return { title: "THE RUNNING SYSTEM", rows: [{ segs: [dim("reading…")] }], actions: [back1] }
      const reload = () => void loadCard().then(draw)
      const show = (k: data.Knob) => (k.value === null ? "off" : k.type === "bool" ? (k.value ? "on" : "off") : String(k.value) || "—")
      const change = (k: data.Knob) => {
        if (k.type === "bool") return void did(data.settingsEdit(k.key, !k.value)).then(reload)
        const range = k.type === "int" ? ` (${k.min}–${k.max}${k.nullable ? ", empty: off" : ""})` : ""
        ask(`${k.key}${range}`, (s) => {
          const t = s.trim()
          const v = k.type === "string" ? t : t === "" && k.nullable ? null : Number(t)
          if (typeof v === "number" && !Number.isInteger(v)) return void (status = `${k.key} wants a whole number`)
          void did(data.settingsEdit(k.key, v)).then(reload)
        }, { text: k.value === null ? "" : String(k.value) })
      }
      const rows: Row[] = settings.knobs.map((k) => ({
        segs: [plain(k.key.padEnd(24)), { s: show(k).padEnd(8), fg: k.value === k.default ? ROLE.prose : ROLE.key }, dim(k.boot ? "on restart  " : "            "), dim(k.doc)],
        open: () => change(k), ref: k,
      }))
      if (settings.restart_pending) rows.unshift({ segs: [key("a restart is scheduled"), dim(" — it runs the moment nobody is mid-turn")] })
      return {
        title: "THE RUNNING SYSTEM · ⏎ changes the selected knob", rows,
        actions: [
          { key: "R", label: "restart the server (waits for quiet)", run: () => void did(data.restart()).then(reload) },
          ...(settings.restart_pending ? [{ key: "x", label: "cancel the scheduled restart", run: () => void did(data.restartCancel()).then(reload) }] : []),
          back1,
        ],
      }
    }
    case "needs": {
      // what waits on you: blocking first (work has stopped), then what to decide; then what's under way
      const row = (n: data.Need): Row => ({
        segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(n.thread_id ? [tidSeg(n.thread_id)] : []),
          { s: n.title, fg: ROLE.prose }, dim(`  ${ago(n.at)}  `), { s: n.text.replace(/\s+/g, " "), fg: n.level === "blocking" ? ROLE.prose : ROLE.inactive }],
        open: n.thread_id ? () => openReader(n.thread_id!, false) : undefined, ref: n,
      })
      const blocking = needs.filter((n) => n.level === "blocking"), deciding = needs.filter((n) => n.level === "decide")
      const live = all.threads.filter((t) => t.live && !t.standing && !needs.some((n) => n.thread_id === t.id))
      const section = (label: string, bg: string, note: string): Row => ({ segs: [{ s: ` ${label} `, fg: ROLE.ground, bg, bold: true }, dim(`  ${note}`)] })
      const rows: Row[] = [
        ...(blocking.length ? [section(`BLOCKING · ${blocking.length}`, ROLE.attention, "work has stopped until you act"), ...blocking.map(row)] : []),
        ...(deciding.length ? [section(`TO DECIDE · ${deciding.length}`, ROLE.body, "nothing waits on these"), ...deciding.map(row)] : []),
        ...(live.length ? [section(`UNDER WAY · ${live.length}`, ROLE.live, "being worked on"), ...live.map((t): Row => ({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, dim(`  ${t.lead ?? ""}${t.stage ? ` · ${t.stage}` : ""}`)], open: () => goThread(t.id, t.workspace_id) }))] : []),
      ]
      const n = rows[sel]?.ref as data.Need | undefined
      const acts: Action[] = !n ? [] : [...needActions(n), { key: "f", label: "one at a time", run: () => open({ kind: "decide", i: Math.max(0, needs.indexOf(n)) }) }]
      return {
        title: needs.length ? `WAITING ON YOU · ${blocking.length} blocking · ${deciding.length} to decide` : "WAITING ON YOU",
        tint: blocking.length ? ROLE.attention : deciding.length ? ROLE.body : ROLE.live,
        rows: rows.length ? rows : [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }],
        actions: [...acts.filter((a, i, all) => all.findIndex((b) => b.key === a.key) === i), back1],
      }
    }
    case "babel": return {
      title: "THE LIBRARY OF BABEL · a page, at random",
      tint: ROLE.inactive,
      rows: mode.page.map((l): Row => ({ segs: [/[a-z]{4,} [a-z]{3,}/.test(l.trim()) && !l.includes(",") ? { s: l, fg: ROLE.attention } : dim(l)] })),
      actions: [{ key: "n", label: "another page", run: openBabel }, back1],
    }
    case "decide": {
      // one waiting item at a time, everything to decide it on the card; acting moves to the next
      const order = [...needs.filter((x) => x.level === "blocking"), ...needs.filter((x) => x.level === "decide")]
      if (!order.length) return { title: "WAITING ON YOU", tint: ROLE.live, rows: [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }], actions: [back1] }
      const i = Math.min(mode.i, order.length - 1), n = order[i]!, tid = n.thread_id ?? null
      const t = tid ? all.threads.find((x) => x.id === tid) : undefined
      const step = (d: number) => open({ kind: "decide", i: (i + d + order.length) % order.length })
      const rows: Row[] = [
        { segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(tid ? [tidSeg(tid)] : []), { s: n.title, fg: ROLE.prose, bold: true }], open: tid ? () => openReader(tid, false) : undefined },
        { segs: [dim(`${n.level === "blocking" ? "work has stopped until you act" : "nothing waits on this"} · ${ago(n.at)}${t ? ` · ${t.lead ?? "no lead"}${t.stage ? ` at ${t.stage}` : ""}` : ""}`)] },
        { segs: [plain("")] },
        ...wrap(n.text, paneW() - 4).map((l): Row => ({ segs: [plain(l)] })),
      ]
      return {
        title: `DECIDE · ${i + 1} of ${order.length}`,
        tint: n.level === "blocking" ? ROLE.attention : ROLE.body,
        rows,
        actions: [...needActions(n), { key: "n", label: "next", run: () => step(1) }, { key: "p", label: "previous", run: () => step(-1) }, { key: "l", label: "the whole list", run: () => open({ kind: "needs" }) }, back1],
      }
    }
    case "ideas": {
      // the banter model wrote these in a coworker's voice: say so, or one reads as their request
      const who = (name: string) => ({ s: `${name}'s voice: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const rows: Row[] = ideas.map((n) => ({ segs: [dim("banter, in "), who(n.author), plain(n.body)], ref: n }))
      const picked = rows[sel]?.ref as CorkNote | undefined, w = ws
      const gone = (id: number) => { ideas = ideas.filter((x) => x.id !== id); room().suggestionBox(ideas) }
      return {
        title: `CORKBOARD IDEAS · ${ideas.length} · written by the office's banter, nobody asked`, rows: rows.length ? rows : [{ segs: [dim("the box is empty. the office's banter drops ideas in it as the crew works.")] }],
        actions: [
          ...(picked && w !== null ? [
            { key: "t", label: "file it as a ticket", run: () => void did(data.ticketFile(w, picked.body)).then(() => data.dropSuggestion(w, picked.id)).then(() => { gone(picked.id); draw() }) },
            { key: "d", label: "throw it out", run: () => void data.dropSuggestion(w, picked.id).then(() => { gone(picked.id); draw() }) },
          ] : []),
          back1,
        ],
      }
    }
    case "arcade": {
      // the coworkers' best scores on the cabinets, where the room keeps them
      const r = room(), highs: Row[] = r instanceof WideRoom ? r.highScores().flatMap((h, i): Row[] => (h ? [{ segs: [key(`cabinet ${i + 1}  `), plain(`best ${h.score}`), dim(`  by ${h.name}`)] }] : [])) : []
      const rows: Row[] = GAMES.map((g): Row => (Bun.which(g.cmd) ? { segs: [plain(g.name.padEnd(16)), dim(g.what)], open: () => play(g) } : { segs: [dim(g.name.padEnd(16)), dim("not installed")] }))
      return {
        title: "ARCADE", rows: [{ segs: [plain("the office's cabinets. a game you leave with ctrl-] waits for you; quitting it brings the room back.")] }, ...highs, ...rows],
        actions: [back1],
      }
    }
    case "pet": {
      const r = room(), wideRoom = r instanceof WideRoom ? r : null
      const doIt = (f: () => unknown) => () => { f(); changed(); draw() }
      // someone mid-turn in this workspace, for a pet to go and cheer on
      const busy = () => all.roster.filter((x) => x.workspace_id === ws && x.thinking).map((x) => x.agent)
      const cheer = (send: (name: string) => boolean) => doIt(() => { const who = busy(); if (who.length) send(who[Math.floor(Math.random() * who.length)]!) })
      if (mode.who === "cat") {
        const draft = (petDraft ??= structuredClone((petsNow ?? resolvePets(loadPets())).cat))
        const named = Object.entries(TEMPERAMENTS).find(([, t]) => AXES.every((a) => t[a] === draft.temperament[a]))?.[0]
        const row = (label: string, value: string, cycle: () => void): Row => ({ segs: [dim(label.padEnd(12)), plain(value)], open: () => { cycle(); draw() } })
        const beat = previewOf(draft, previewTick)
        const rows: Row[] = [
          { segs: [plain("your cat, and a princess. she does what you ask — if she feels like it — then her own day carries on.")] },
          { segs: [dim("name".padEnd(12)), plain(draft.name)] },
          row("species", draft.species, () => { draft.species = cycleVal(["cat", "rabbit", "bird"] as const, draft.species as "cat") }),
          row("temperament", named ?? "custom", () => { const names = Object.keys(TEMPERAMENTS); draft.temperament = { ...TEMPERAMENTS[names[(names.indexOf(named ?? "") + 1) % names.length]!]! } }),
          ...AXES.map((a) => row(a, dots(draft.temperament[a]), () => { draft.temperament[a] = cycleAxis(draft.temperament[a]) })),
          { segs: [dim("preview".padEnd(12)), plain(`${{ sleep: "z", sit: "·", play: "o", walk: ">" }[beat.mode]} ${beat.line}`)] },
        ]
        return {
          title: `${draft.name.toUpperCase()}`, rows,
          actions: [
            { key: "S", label: "save her temperament", run: () => { savePets({ cat: { species: draft.species, temperament: named ?? { ...draft.temperament } } }); petsSeen = ""; followPets(); back(); roomChanged = true; draw() } },
            { key: "p", label: "pat her", run: doIt(() => r.pet()) },
            { key: "z", label: "the zoomies", run: doIt(() => r.catDo("zoomies")) },
            { key: "y", label: "play with the yarn", run: doIt(() => r.catDo("play")) },
            { key: "c", label: "come to my desk", run: doIt(() => r.catDo("come")) },
            { key: "s", label: "go have a nap", run: doIt(() => r.catDo("nap")) },
            ...(busy().length ? [{ key: "g", label: "go cheer someone on", run: cheer((name) => r.catCheer(name)) }] : []),
            ...(busy().length ? [{ key: "l", label: "Nina carries a letter", run: cheer((name) => r.catLetter(name)) }] : []),
            back1,
          ],
        }
      }
      return {
        title: "ARGOS", rows: [{ segs: [plain(wideRoom ? "the office dog. good boy." : "Argos lives in the wide room — make the terminal wider to see him.")] }],
        actions: wideRoom ? [
          { key: "p", label: "pat him", run: doIt(() => wideRoom.patDog()) },
          { key: "w", label: "go for a walk", run: doIt(() => wideRoom.dogDo("walk")) },
          { key: "o", label: "come to my office", run: doIt(() => wideRoom.dogDo("office")) },
          { key: "s", label: "sit", run: doIt(() => wideRoom.dogDo("sit")) },
          { key: "b", label: "bed", run: doIt(() => wideRoom.dogDo("bed")) },
          ...(busy().length ? [{ key: "g", label: "go cheer someone on", run: cheer((name) => wideRoom.dogCheer(name)) }] : []),
          back1,
        ] : [back1],
      }
    }
    case "look": {
      const name = mode.name
      const draft = (lookDraft ??= { ...lookOf(name), ...overrideFor(name) })
      const field = (label: string, value: string, cycle: () => void): Row => ({ segs: [dim(label.padEnd(12)), plain(value)], open: () => { cycle(); draw() } })
      const rows: Row[] = [
        { segs: [dim("look at the room — a saved change shows there live, with no restart")] },
        field("hair", draft.hair ?? "", () => { draft.hair = cycleVal(HAIR_STYLES, draft.hair!) }),
        field("hair colour", draft.hairRole ?? "", () => { draft.hairRole = cycleVal(HAIR_ROLES, draft.hairRole!) }),
        field("skin", draft.skinRole ?? "default", () => { draft.skinRole = cycleOpt(SKIN_ROLES, draft.skinRole) }),
        field("outfit", draft.outfit ?? "none", () => { draft.outfit = cycleOpt(Object.keys(OUTFIT) as Outfit[], draft.outfit) }),
        field("accessory", draft.accessory ?? "none", () => { draft.accessory = cycleOpt(Object.keys(ACCESSORY) as Accessory[], draft.accessory) }),
        field("build", draft.body ?? "average", () => { draft.body = cycleVal(BODIES, draft.body ?? "average") }),
        ...SLOTS.map((slot) => field(slot, draft.parts?.[slot]?.id ?? "none", () => {
          const next = nextPart(slot, draft.parts?.[slot]), parts = { ...draft.parts }
          if (next) parts[slot] = next; else delete parts[slot]
          draft.parts = parts
        })),
      ]
      return {
        title: `LOOK · ${name.toUpperCase()}`, rows,
        actions: [
          // not "enter": rows[sel].open() (field-cycling) owns Enter here, same as every other card with cycled rows
          { key: "s", label: "save", run: () => { saveLook(name, draft); lookDraft = null; back(); roomChanged = true; draw() } },
          { key: "r", label: "roll", run: () => { Object.assign(draft, rollLook(`${name}:${rolls++}`)); draw() } },
          { key: "e", label: "draw a custom look", run: () => {
            editBuf = { front: draft.custom?.front ? [...draft.custom.front] : blankBuf(), side: draft.custom?.side ? [...draft.custom.side] : blankBuf(), back: draft.custom?.back ? [...draft.custom.back] : blankBuf() }
            editEntry = { front: [...editBuf.front], side: [...editBuf.side], back: [...editBuf.back] }
            editCursor = { x: 0, y: 0 }; editScroll = 0
            mode = { kind: "look-editor", name, view: "front" }; sel = 0; snapSel = true; draw()
          } },
          back1,
        ],
      }
    }
    case "look-editor": {
      const { name, view } = mode
      if (!editBuf) { editBuf = { front: blankBuf(), side: blankBuf(), back: blankBuf() } }
      const draft = (lookDraft ?? { ...lookOf(name), ...overrideFor(name) }) as Look
      const paint = paints(shirtOf(null), draft)
      const WIN = 11
      if (editCursor.y < editScroll + 1) editScroll = Math.max(0, editCursor.y - 1)
      else if (editCursor.y > editScroll + WIN - 2) editScroll = Math.min(22 - WIN, editCursor.y - (WIN - 2))
      const legend: Seg[] = LEGEND_CHARS.flatMap((ch) => [{ s: ch, fg: paint[ch] ?? ROLE.inactive }, plain(" ")])
      const rows: Row[] = [{ segs: legend }]
      const buf = editBuf[view]!
      for (let y = editScroll; y < Math.min(22, editScroll + WIN); y++) {
        const r = buf[y]!, segs: Seg[] = []
        for (let x = 0; x < 12; x++) {
          const ch = r[x]!, color = ch === "." ? ROLE.inactive : (paint[ch] ?? ROLE.inactive), atCursor = y === editCursor.y && x === editCursor.x
          segs.push(atCursor ? { s: "█", fg: ROLE.ground, bg: color } : { s: ch === "." ? "·" : "█", fg: color })
        }
        rows.push({ segs })
      }
      rows.push({ segs: [dim(`1/2/3 view (${view}) · m mirror (${editMirror ? "on" : "off"}) · letter paints · . clears · ⏎ save · esc discard`)] })
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
  if (kitty && cell) {
    for (let k = Math.min(5, Math.floor(((rowsN - DETAIL - 3) * cell.h) / WIDE_H)); k >= 2 && next === null; k--) {
      const w = Math.floor((colsN * cell.w) / k)
      if (w >= WIDE_MIN_W) next = w
    }
  }
  if (next !== wide) { wide = next; rooms.clear() }
  g = { ...(wide ? geometry(wide, (r0 => (r0 instanceof WideRoom ? r0.height : WIDE_H))(room()), colsN, rowsN, DETAIL + 3, cell, kitty, WIDE_H) : geometry(W, H, colsN, rowsN, DETAIL + 3, cell, kitty)), row: 1 }
  const vw = Math.min(g.floorW, (g.cols * g.cw) / g.k), vh = Math.min(g.floorH, (g.rows * g.ch) / g.k)
  viewport = follow
    ? centerViewport({ x: 0, y: 0, w: vw, h: vh }, OFF_W / 2, (BAND + OFF_DOOR) / 2, g.floorW, g.floorH)
    : centerViewport({ ...viewport, w: vw, h: vh }, viewport.x + viewport.w / 2, viewport.y + viewport.h / 2, g.floorW, g.floorH)
  frame = null; sentImage = false
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
}

function draw() {
  if (!g || zoom) return
  const colsN = cols(), termRows = process.stdout.rows ?? 40
  if (reader) {
    if (picker || confirm) { out(`${ESC}[?25l` + drawOverlay(colsN, termRows)); return }
    out(reader.draw(colsN, termRows, threadOf(reader.tid), [...threadActions(reader.tid, true).map((x) => `${x.key} ${x.label}`), "pgup/pgdn scroll", "esc back"].join(" · ")))
    return
  }
  const a = view()
  let o = `${ESC}[?2026h${ESC}[?25l`
  // header: the workspace, and what waits elsewhere
  const blocking = needs.filter((n) => n.level === "blocking").length, deciding = needs.length - blocking
  const head: (Seg & { go?: () => void })[] = [{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(), fg: ROLE.body, bold: true }, key(" › "),
    ...(all.ok ? [] : [{ s: `  ${all.note ?? "channel down"}`, fg: ROLE.alarm }]),
    ...(blocking ? [{ s: `  ⚑ ${blocking} blocking `, fg: ROLE.ground, bg: ROLE.attention, bold: true, go: inbox }] : []),
    ...(deciding ? [{ s: `  ${blocking ? "· " : "⚑ "}${deciding} to decide`, fg: ROLE.body, go: inbox }] : []),
    ...(needs.length ? [{ ...dim("  (i)"), go: inbox }] : []),
    ...(shiftHeader() ? [{ s: `  ${shiftHeader()}`, fg: ROLE.body, go: toggleShift }] : []),
    ...(lifeHeader(all, ws) ? [{ s: `  ${lifeHeader(all, ws)}`, fg: ROLE.body }, dim("  (L)")] : []),
    ...(updated() ? [{ s: "  office updated · R reloads", fg: ROLE.live, bold: true }] : []),
    ...(all.health?.state === "warn" ? [{ s: `  ⚠ ${all.health.problems[0]}`, fg: ROLE.alarm, go: () => open({ kind: "health" }) }] : []),
    ...(process.env.OFFICE_DEBUG ? [dim(`  viewport ${Math.round(viewport.x)},${Math.round(viewport.y)}`)] : [])]
  headHits = []
  let hx = 1
  for (const s of head) { const w = cells(s.s); if (s.go) headHits.push({ from: hx, to: hx + w - 1, go: s.go }); hx += w }
  o += `${ESC}[1;1H` + line(head, colsN)
  // the room
  const room0 = room()
  const building = mode.kind === "build" && build !== null
  const fresh = !frame
  // leaving build mode puts the room back, however the mode was left
  if (!building && homeShown) {
    roomChanged = true; imageDirty = true
    homeNow = loadHome()
    for (const r of rooms.values()) if (r instanceof WideRoom) r.setHome(homeNow)
  }
  homeShown = building
  const vp = building ? { x: 0, y: 0, w: viewport.w, h: viewport.h } : viewport
  if (building) {
    frame = renderHome({ home: build!.home, cursor: build!.cursor, carrying: build!.carrying, refused: build!.refused, w: Math.ceil(vp.w), h: Math.ceil(vp.h), weather: a.weather?.kind, mail: mailbox(needs) })
    imageDirty = true
  } else if (fresh || roomChanged) { frame = room0.render(a, { picked, armed: null, person: mode.kind === "person" ? mode.name : null, tray: unread(), board: boardCtx() }, measureFor(g), world?.now()); roomChanged = false }
  const seen = clipFrame(frame!, vp)
  if (g.kitty && (!sentImage || fresh || imageDirty || panned)) { o += kittyImage(seen, g, vp); sentImage = true; imageDirty = false }
  if (!g.kitty) textLayer(seen, g, vp).forEach((l, i) => { o += `${ESC}[${g.row + 1 + i};${g.col + 1}H${l}` })
  panned = false
  // the tip line: what the pointer is over, or what just happened
  const tipRow = g.row + g.rows + 1
  o += `${ESC}[${tipRow};1H` + line([tip ? dim(` ${tip.split("\n").join(" · ")}`) : status ? key(` ${status}`) : dim("")], colsN)
  out(o + drawPane(tipRow + 1, colsN, termRows) + `${ESC}[?2026l`)
}

// what the pane last drew, for a click on it: where it starts, how wide its left side is, which
// row and which action each of its lines shows
let acts: Action[] = [], asel = 0, pane = { top: 0, leftW: 0, room: 0, first: 0, rowAt: [] as (number | undefined)[], actAt: [] as (number | undefined)[] }
/** how far a card whose rows have nothing to open is scrolled down; Infinity keeps a thread's tail in view */
let scroll = 0
const ACTIONS_W = 34
const keyName = (k: string) => ({ space: "␣", enter: "⏎", right: "→", left: "←" })[k] ?? k
/** the actions take j/k and enter when the card's rows have nothing to open */
const actionsFocused = () => !rows.some((r) => r.open)
/** the keys that work everywhere a card's own actions don't claim them */
const GLOBALS: Hint[] = [{ key: "/", label: "find" }, { key: "'", label: "talk to the office" }, { key: "i", label: "inbox" }, { key: "tab", label: "crew" }, { key: "[ ]", label: "workspace" }, { key: "esc", label: "back" }, { key: "q", label: "quit" }]
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
  acts = []
  if (picker) {
    const shown = rank(picker.q.text, picker.items, (p) => p.text)
    picker.sel = Math.min(picker.sel, Math.max(0, shown.length - 1))
    title = `${picker.title}: ${picker.q.text}`
    segRows = shown.map((p) => ({ segs: p.segs, open: p.run }))
    keys = "type to narrow · ↑↓ move · enter pick · esc close"
    cursor = { r: -1, c: title.length + 1 }
    sel = picker.sel
  } else if (input?.ed.multiline) {
    const v = input.ed.view(colsN - 6, Math.max(1, termRows - top - 3))
    title = input.label
    segRows = [{ segs: cyclesSegs(input) }, ...v.rows.map((r) => ({ segs: [pink(" ▌ "), plain(r)] }))]
    keys = `enter done · alt-enter newline${input.cycles?.length ? ` · tab change the lit choice${input.cycles.length > 1 ? " · shift-tab the next choice" : ""}` : ""} · esc cancel`
    cursor = { r: v.cursor.r + 1, c: v.cursor.c + 3 }
  } else {
    const d = detail()
    title = d.title; segRows = d.rows; acts = d.actions; tint = d.tint ?? ROLE.key
  }
  rows = segRows
  const split = acts.length > 0 && colsN >= 80
  const leftW = split ? colsN - ACTIONS_W - 1 : colsN
  const selectable = rows.some((r) => r.open) && !input
  if (snapSel && selectable && !picker) { snapSel = false; if (!rows[sel]?.open) sel = rows.findIndex((r) => r.open) }
  if (sel >= rows.length) sel = Math.max(0, rows.length - 1)
  if (asel >= acts.length) asel = Math.max(0, acts.length - 1)
  // the foot lists what the actions column can't show (all of it, with no column), then the globals;
  // its height and the column's room depend on each other, so settle them together
  const claimed = new Set(acts.map((x) => x.key))
  const globals = [...(world ? PLAY : []), ...GLOBALS.filter((h) => !h.key.split(" ").some((k) => claimed.has(k)))]
  let footN = 1, room = 0, win: Window, awin: Window = { first: 0, count: 0, above: 0, below: 0 }, foot: Hint[][] = []
  for (let pass = 0; pass < 3; pass++) {
    room = Math.max(1, termRows - footN - 1 - top)
    win = cursor && input ? offset(rows.length, room, 0) : selectable || picker ? followSel(rows.length, sel, room) : offset(rows.length, room, scroll)
    if (split) awin = !selectable ? followSel(acts.length, asel, room) : offset(acts.length, room, 0)
    const hidden = split ? acts.filter((_, i) => i < awin.first || i >= awin.first + awin.count) : acts
    foot = keys ? [] : footLines([...hidden.map((x) => ({ key: keyName(x.key), label: x.label })), ...globals], colsN - 2, Math.max(1, Math.floor((termRows - top - 1) / 2)))
    const n = Math.max(1, foot.length)
    if (n === footN) break
    footN = n
  }
  win = win!
  if (!selectable && !picker && !input && Number.isFinite(scroll)) scroll = win.first
  const bar = (t: string, w: number, bg: string) => line([{ s: ` ${t} `, fg: ROLE.ground, bg }, dim(" " + "─".repeat(Math.max(0, w - cells(t) - 3)))], w)
  o += `${ESC}[${top};1H` + bar(title, leftW, picker || input ? ROLE.attention : tint) + (split ? line([dim("┬")], 1) + bar("ACTIONS", ACTIONS_W, ROLE.key) : "")
  const how = selectable || picker ? "" : " · pgup/pgdn"
  pane = { top, leftW, room, first: win.first, rowAt: [], actAt: [] }
  for (let i = 0; i < room; i++) {
    const at = lineOf(win, i), r = at !== undefined && at >= 0 ? rows[at] : undefined
    pane.rowAt.push(r ? at : undefined)
    const mark = r && selectable && at === sel && mode.kind !== "thread" && mode.kind !== "person" ? key("▸ ") : plain("  ")
    o += `${ESC}[${top + 1 + i};1H` + line(r ? [mark, ...r.segs] : at !== undefined ? more(win, at, how) : [], leftW)
    if (split) {
      const ai = lineOf(awin, i), x = ai !== undefined && ai >= 0 ? acts[ai] : undefined
      pane.actAt.push(x ? ai : undefined)
      const lit = x && !selectable && ai === asel
      o += `${ESC}[${top + 1 + i};${leftW + 1}H` + line([dim("│")], 1) + line(x ? [lit ? key("▸") : plain(" "), { s: ` ${keyName(x.key).padStart(5)} `, fg: ROLE.key, bold: true }, { s: fit(x.label, ACTIONS_W - 8), fg: x.key === "esc" ? ROLE.inactive : ROLE.prose }] : ai !== undefined ? more(awin, ai, selectable ? " · in the foot" : "") : [], ACTIONS_W)
    }
  }
  // the foot: what you are typing, a confirm, or the keys — the lit one when the actions have them and no column shows it
  o += `${ESC}[${termRows - footN};1H` + line([], colsN)
  const one = input && !input.ed.multiline ? input : null
  const litKey = !split && !selectable && acts[asel] ? keyName(acts[asel]!.key) : null
  const hintSegs = (l: Hint[]): Seg[] => l.flatMap((h, j): Seg[] => [...(j ? [dim(" · ")] : []), h.key === litKey ? { s: `${h.key} ${h.label}`, fg: ROLE.ground, bg: ROLE.key } : { s: h.key, fg: ROLE.key, bold: true }, ...(h.key === litKey ? [] : [plain(` ${h.label}`)])])
  const feet: Seg[][] = one ? [[pink(` ${one.label}: `), plain(one.ed.text), ...(one.cycles?.length ? [dim("   tab: "), ...cyclesSegs(one)] : [])]] : confirm ? [[pink(` ${confirm.label} (y/n)`)]] : keys ? [[dim(` ${keys}`)]] : foot.map((l) => [plain(" "), ...hintSegs(l)])
  for (let i = 0; i < footN; i++) o += `${ESC}[${termRows - footN + 1 + i};1H` + line(feet[i] ?? [], colsN)
  o += `${ESC}[?7h`
  if (one) {
    const pre = [...` ${one.label}: `].length
    o += `${ESC}[${termRows};${pre + one.ed.col + 1}H${ESC}[?25h`
  } else if (cursor && cursor.r >= 0) o += `${ESC}[${top + 1 + cursor.r};${cursor.c + 3}H${ESC}[?25h`
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
  const i = input!
  if (k === "esc") { input = null; return draw() }
  if (k === "enter") { input = null; i.submit(i.ed.text, (i.cycles ?? []).map((c) => c.values[c.i]!.value)); return draw() }
  if ((k === "tab" || k === "backtab") && i.cycles?.length) {
    if (k === "backtab") i.focus = (i.focus + 1) % i.cycles.length
    else { const c = i.cycles[i.focus]!; c.i = (c.i + 1) % c.values.length }
    return draw()
  }
  i.ed.key(k)
  draw()
}
function pickerKey(k: string) {
  const p = picker!
  const shown = rank(p.q.text, p.items, (x) => x.text)
  if (k === "esc") { picker = null; return draw() }
  if (k === "enter") { const it = shown[p.sel]; picker = null; it?.run(); return draw() }
  if (k === "down" || k === "ctrl-n" || k === "tab") { p.sel = Math.min(p.sel + 1, shown.length - 1); return draw() }
  if (k === "up" || k === "ctrl-p" || k === "backtab") { p.sel = Math.max(p.sel - 1, 0); return draw() }
  if (p.q.key(k)) p.sel = 0
  draw()
}

function paintAt(ch: string) {
  if (mode.kind !== "look-editor" || !editBuf) return
  const view = mode.view, row = editBuf[view]![editCursor.y]!.split("")
  row[editCursor.x] = ch
  if (editMirror) row[11 - editCursor.x] = ch
  editBuf[view]![editCursor.y] = row.join("")
  draw()
}

function editorKey(k: string) {
  if (mode.kind !== "look-editor" || !editBuf) return
  const { name, view } = mode
  if (k === "up") { editCursor.y = Math.max(0, editCursor.y - 1); return draw() }
  if (k === "down") { editCursor.y = Math.min(21, editCursor.y + 1); return draw() }
  if (k === "left") { editCursor.x = Math.max(0, editCursor.x - 1); return draw() }
  if (k === "right") { editCursor.x = Math.min(11, editCursor.x + 1); return draw() }
  if (k === "m") { editMirror = !editMirror; return draw() }
  if (k === "1" || k === "2" || k === "3") {
    mode = { kind: "look-editor", name, view: k === "1" ? "front" : k === "2" ? "side" : "back" }
    return draw()
  }
  if (k === "esc") {
    if (editEntry) editBuf[view] = [...editEntry[view]]
    mode = { kind: "look", name }; sel = 0; snapSel = true; return draw()
  }
  if (k === "enter") {
    if (lookDraft) {
      const custom = trimCustom(editBuf)
      if (custom) lookDraft.custom = custom
      else delete lookDraft.custom
    }
    mode = { kind: "look", name }; sel = 0; snapSel = true; return draw()
  }
  if (k === ".") return paintAt(".")
  if (LEGEND_CHARS.includes(k)) return paintAt(k)
}

// the last keys pressed, for the Konami code
let keyLog: string[] = []

/** sandbox only: one key, one thing to do with the toy; true when the key was one of them */
function toyKey(k: string): boolean {
  if (!world) return false
  const r = room(), under = mode.kind === "person" ? mode.name : null
  switch (k) {
    case "d": r.play("doorbell"); status = "ding dong"; break
    case "e": r.play("event"); status = "something's up"; break
    case "f": r.play("drill"); status = "fire drill!"; break
    case "t": r.catDo("come"); if (r instanceof WideRoom) r.dogDo("office"); status = "treat! they come running"; break
    case "n": world.toggleNight(); for (const x of rooms.values()) x.setClock(world.now); status = world.now().getHours() === 23 ? "night falls" : "morning"; break
    case "w": world.nextWeather(); status = `weather: ${world.snapshot().weather!.desc.toLowerCase()}`; void refresh(); break
    case "p": if (mode.kind === "pet" && mode.who === "dog" && r instanceof WideRoom) r.patDog(); else if (under) r.pat(under); else r.pet(); status = "pat pat"; break
    case "c": world.callOver(under ?? world.snapshot().bench[1]!.name); status = `calling someone over to ${under ?? "the desk"}`; void refresh(); break
    default: return false
  }
  changed(); draw(); return true
}

function onKey(k: string) {
  keyLog = [...keyLog, k].slice(-KONAMI.length)
  if (isKonami(keyLog)) { keyLog = []; room().disco(); status = "↑↑↓↓←→←→BA — everybody dance"; changed(); return draw() }
  if (picker) return pickerKey(k)
  if (input) return inputKey(k)
  if (confirm) { const c = confirm; confirm = null; if (k === "y") c.run(); return draw() }
  if (mode.kind === "look-editor") return editorKey(k)
  if (reader) {
    const r = reader.key(k, Math.max(1, (process.stdout.rows ?? 24) - 6))
    if (r === "leave") return closeReader()
    if (r === "pass") return threadActions(reader.tid, true).find((x) => x.key === k)?.run()
    if (r !== "done") void r.then(draw)
    return draw()
  }
  if (toyKey(k)) return
  // the card's own actions first: a key there means what its actions pane says
  const name = k === " " ? "space" : k
  const own = detail().actions.find((x) => x.key === name)
  if (own) return own.run()
  const onActions = actionsFocused()
  switch (k) {
    case "q": case "ctrl-c": return quit()
    case "esc": back(); roomChanged = true; return draw()
    case "[": return stepWs(-1)
    case "]": return stepWs(1)
    case "tab": case "backtab": {
      const crew = crewOf(view())
      if (!crew.length) return
      const i = mode.kind === "person" ? crew.findIndex((c) => c.name === (mode as { name: string }).name) : -1
      return open({ kind: "person", name: crew[(i + (k === "tab" ? 1 : -1) + crew.length) % crew.length]!.name })
    }
    case "j": case "down":
      snapSel = false
      if (onActions) asel = Math.min(asel + 1, acts.length - 1); else sel = Math.min(sel + 1, rows.length - 1)
      return draw()
    case "k": case "up":
      snapSel = false
      if (onActions) asel = Math.max(asel - 1, 0); else sel = Math.max(sel - 1, 0)
      return draw()
    case "left": if (mode.kind === "column") return open({ kind: "column", col: (mode.col + COLS.length - 1) % COLS.length }); return
    case "shift-up": case "shift-down": case "shift-left": case "shift-right": {
      const dx = g.cw / g.k, dy = g.ch / g.k
      const [ddx, ddy] = k === "shift-left" ? [-dx, 0] : k === "shift-right" ? [dx, 0] : k === "shift-up" ? [0, -dy] : [0, dy]
      viewport = panViewport(viewport, ddx, ddy, g.floorW, g.floorH); follow = false; panned = true
      return draw()
    }
    case ".":
      viewport = centerViewport(viewport, OFF_W / 2, (BAND + OFF_DOOR) / 2, g.floorW, g.floorH); follow = true; panned = true
      return draw()
    case ",": {
      const need = needs[0]
      const seat = need ? all.roster.find((r) => r.thread_id === need.thread_id) : null
      const at = seat ? room().at(seat.agent) : null
      if (!at) return
      viewport = centerViewport(viewport, at.x, at.y, g.floorW, g.floorH); panned = true
      return draw()
    }
    case "pgdn": case "pgup": return page(k === "pgdn" ? 1 : -1)
    case "enter": return onActions ? acts[asel]?.run() : rows[sel]?.open?.()
    case "/": case "ctrl-k": return void finder()
    case "i": return inbox()
    case "R": if (updated()) void relaunch(); return
    case "'": return talk(null)
    case "n": return newThread()
    case "N": return newTicket()
    case "c": return open({ kind: "crew" })
    case "t": return open({ kind: "column", col: 0 })
    case "o": return open({ kind: "notes" })
    case "f": return open({ kind: "archive" })
    case "a": return open({ kind: "calendar" })
    case "w": return open({ kind: "tray" })
    case "!": return open({ kind: "triage" })
    case "H": return open({ kind: "health" })
    case "b": return open({ kind: "memory" })
    case "L": if (all.life?.[String(ws)]) open({ kind: "life" }); return
    case "B": if (flagOn(all, "build_mode")) open({ kind: "build" }); return
    case "W": return open({ kind: "boss" })
    case "p": room().pet(); changed(); return draw()
  }
}

/** a page of the card's rows, by the selection when they open, else by the view */
function page(dir: 1 | -1, by = Math.max(1, pane.room - 2)) {
  snapSel = false
  if (actionsFocused()) scroll = Math.max(0, (Number.isFinite(scroll) ? scroll : pane.first) + dir * by)
  else sel = Math.max(0, Math.min(sel + dir * by, rows.length - 1))
  draw()
}

function onPaste(text: string) {
  if (picker) { picker.q.insert(text); return draw() }
  if (input) { input.ed.insert(text); return draw() }
  if (reader) { reader.paste(text); return draw() }
}

function onMouse(m: Extract<Input, { t: "mouse" }>) {
  if (!frame || !g || reader) return
  const inRoom0 = m.row - 1 >= g.row && m.row - 1 < g.row + g.rows
  if (m.motion && m.button === 0) {
    if (inRoom0 && drag) {
      const dx = (drag.col - m.col) * (g.cw / g.k), dy = (drag.row - m.row) * (g.ch / g.k)
      viewport = panViewport(viewport, dx, dy, g.floorW, g.floorH); follow = false; panned = true
      drag = { col: m.col, row: m.row }
      return draw()
    }
    if (inRoom0) drag = { col: m.col, row: m.row }
    return
  }
  drag = null
  // the wheel over the pane scrolls it
  if (m.press && (m.button === 64 || m.button === 65) && m.row > pane.top) return page(m.button === 65 ? 1 : -1, 3)
  const h = hitAt(clipFrame(frame, viewport), g, m.col, m.row, viewport)
  if (m.motion) { const t = h?.tip ?? ""; if (t !== tip) { tip = t; draw() } return }
  if (!m.press || m.button !== 0) return
  if (m.row === 1) return headHits.find((x) => m.col >= x.from && m.col <= x.to)?.go()
  const inRoom = inRoom0
  if (h) return act(h.act)
  // a click on bare floor clears the slate, as on the desktop
  if (inRoom) { back(true); roomChanged = true; return draw() }
  // the pane: a click on an action runs it, on a row opens it
  const i = m.row - pane.top - 1
  if (i < 0) return
  if (m.col > pane.leftW + 1) {
    const ai = pane.actAt[i], x = ai === undefined ? undefined : acts[ai]
    if (x) { asel = ai!; x.run() }
    return
  }
  const ri = pane.rowAt[i], r = ri === undefined ? undefined : rows[ri]
  if (r?.open) { sel = ri!; r.open() }
}

// ── zoomed into a terminal ─────────────────────────────────────────────────────────────────────
// The whole screen is one coworker's terminal: a bar on top, every key to the pane but Ctrl-],
// which brings the room back.
let zoom: { view: TerminalView; label: string } | null = null
const ROOM_KEY = 0x1d // Ctrl-]

async function zoomInto(tid: number) {
  const target = await data.terminal(tid)
  if (!target) { status = `#${tid} has no live terminal`; if (reader) reader.status = status; return draw() }
  zoomOn(target, `#${tid} ${threadOf(tid)?.lead ?? target.window} · terminal`)
}
/**
 * lazygit in the thread's worktree, in a tmux session the office keeps (`-L tlon-office`, one per
 * thread), so it is where you left it next time; quitting lazygit closes the window and the zoom.
 */
const OWN_TMUX = "tlon-office"
async function zoomGit(tid: number) {
  if (!Bun.which("lazygit")) { status = "lazygit is not installed"; return draw() }
  const path = await data.worktree(tid)
  if (!path) { status = `#${tid} has no repo to show`; return draw() }
  const session = `git-${tid}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "lazygit", "-c", path, "lazygit")
  zoomOn({ socket: OWN_TMUX, session, window: "lazygit" }, `#${tid} ${threadOf(tid)?.lead ?? ""} · git`)
}
/** a workline's docs, picked from a list */
async function pickDoc(tid: number) {
  const names = await data.docs(tid)
  if (!names.length) { status = `#${tid} has no docs yet`; return draw() }
  find(`DOCS · #${tid}`, names.map((n) => ({ segs: [{ s: n, fg: ROLE.prose }], text: n, run: () => { picker = null; void readDoc(tid, n) } })))
}
/** a doc read in the office's own tmux: glow renders markdown, else bat, else less */
async function readDoc(tid: number, name: string) {
  const text = await data.doc(tid, name)
  if (text === null) { status = `#${tid}: no ${name}`; return draw() }
  const dir = `${process.env.XDG_RUNTIME_DIR ?? "/tmp"}/tlon-office`, file = `${dir}/doc-${tid}-${name}`
  mkdirSync(dir, { recursive: true }); writeFileSync(file, text)
  const session = `doc-${tid}-${name.replace(/\W/g, "_")}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  tmux("kill-session", "-t", `=${session}`)
  const show = `if command -v glow >/dev/null; then glow -p "$0"; elif command -v bat >/dev/null; then bat --paging=always --style=plain -l md "$0"; else less "$0"; fi`
  tmux("new-session", "-d", "-s", session, "-n", "doc", "sh", "-c", show, file)
  zoomOn({ socket: OWN_TMUX, session, window: "doc" }, `#${tid} · ${name}`)
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
]
/** a game in the office's own tmux, one session each, so a game you leave is where you left it */
function play(g: (typeof GAMES)[number]) {
  const session = `arcade-${g.cmd}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "game", g.cmd)
  zoomOn({ socket: OWN_TMUX, session, window: "game" }, `arcade · ${g.name}`)
}
function zoomOn(target: Target, label: string) {
  const colsN = cols(), rowsN = Math.max(2, (process.stdout.rows ?? 24) - 1)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[?1003l${ESC}[?1006l${ESC}[?2004l${ESC}[2J`)
  zoom = { label, view: new TerminalView(target, colsN, rowsN, () => drawZoom(), () => leaveZoom()) }
  drawZoom()
}
function drawZoom() {
  if (!zoom) return
  const colsN = cols(), vt = zoom.view.vt
  // no autowrap while drawing: a row the VT and this terminal measure differently can't wrap and scroll the bar away
  let o = `${ESC}[?2026h${ESC}[?7l${ESC}[?25l${ESC}[1;1H` + line([{ s: " ROOM ", fg: ROLE.ground, bg: ROLE.attention }, key(" ctrl-] "), { s: zoom.label, fg: ROLE.body, bold: true }], colsN)
  vtRows(vt).forEach((r, i) => { o += `${ESC}[${i + 2};1H${r}` })
  const b = vt.buffer.active
  o += `${ESC}[?7h${ESC}[${b.cursorY + 2};${b.cursorX + 1}H${ESC}[?25h${ESC}[?2026l`
  out(o)
}
function leaveZoom() {
  if (!zoom) return
  const z = zoom
  zoom = null
  z.view.close()
  out(`${ESC}[0m${ESC}[?25l${ESC}[?1003h${ESC}[?1006h${ESC}[?2004h`)
  if (reader) { out(`${ESC}[2J`); return draw() }
  layoutScreen(); draw()
}
/** raw keys while zoomed: Ctrl-] leaves, the rest goes to the pane as it came */
function zoomInput(b: Uint8Array) {
  const at = b.indexOf(ROOM_KEY)
  if (at < 0) return zoom?.view.send(b)
  zoom?.view.send(b.subarray(0, at))
  leaveZoom()
}

function quit() { zoom?.view.close(); leave(); process.exit(0) }

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
      if (zoom) return zoomInput(b)
      const { inputs, rest } = tokenize(pending + b.toString("utf8"))
      pending = rest
      for (const i of inputs) {
        if (i.t === "cell") cell = { w: i.w, h: i.h }
        else if (i.t === "graphics") kitty = process.env.OFFICE_GRAPHICS !== "blocks" && i.ok
        else if (i.t === "da") { if (!detected) { detected = true; res() } }
        else if (!detected) continue
        else if (i.t === "key") onKey(i.key)
        else if (i.t === "paste") onPaste(i.text)
        else if (i.t === "mouse") onMouse(i)
      }
    })
    setTimeout(() => { if (!detected) { detected = true; res() } }, 500)
  })
  query()
  await ready
  // tmux eats the graphics protocol unless told to pass it through; blocks there by default
  if (process.env.TMUX && process.env.OFFICE_GRAPHICS !== "kitty") kitty = false
  layoutScreen()
  process.stdout.on("resize", () => {
    if (zoom) { zoom.view.resize(cols(), Math.max(2, (process.stdout.rows ?? 24) - 1)); return drawZoom() }
    query(); setTimeout(() => { layoutScreen(); draw() }, 150)
  })
  await refresh()
  every(refresh, 10_000)
  every(pollPlayer, 2000)
  every(() => { if (mode.kind === "pet" && petDraft) { previewTick += 10; draw() } }, 1000)
  every(() => { if (followPalette() || followLooks() || followSouls() || followPets()) { frame = null; draw() } }, 1000)
  // another surface (the desktop's alert) asks to show a thread: open it, once per request, ignoring
  // what was asked before this TUI started
  let seenFocus = (await data.focus())?.at ?? 0
  every(async () => {
    const f = await data.focus()
    if (!f || f.at <= seenFocus) return
    seenFocus = f.at
    if (zoom) leaveZoom()
    goThread(f.thread_id, threadOf(f.thread_id)?.workspace_id)
    openReader(f.thread_id, false)
  }, 1000)
  // a card showing a running coworker keeps their activity current
  every(() => {
    const tid = openThread()
    if (tid !== null && !zoom && !reader && threadOf(tid)?.live && !talkView.has(tid)) void pollActivity(tid).then((moved) => { if (moved) draw() })
  }, 1000)
  // the room's clock: 10 Hz, drawn only when it changed
  every(() => { if (!reader && room().step(view())) { changed(); draw() } }, 100)
}
main()
