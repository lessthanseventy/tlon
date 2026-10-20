// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { arrivals } from "../kit/door"
import { babelPage, isKonami, KONAMI } from "../kit/eggs"
import { existsSync, mkdirSync, readFileSync, realpathSync, statSync, unlinkSync, watchFile, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { personaLines } from "../kit/persona"
import { FLOOR, Looks, marginInk, type Note } from "../kit/margin"
import { seatLine } from "../kit/seat-voices"
import { load as loadWhim, save as saveWhim } from "../kit/whimsy-file"
import { resolve as resolveWhim, type State as WhimState } from "../kit/whimsy"
import { resetToPreset, whimsyRows, whimsyTitle } from "./whimsy-card"
import { ledgerLines, MUG, NAMEPLATE, newLedger, SHERIFF, tickFromTriage, type Ledger } from "../kit/scharlach"
import { boardColumns, busiest, cardState, COLS, crewOf, epicChildren, needsYou, BOARD_LEGEND, STATE_GLYPH, statusGlyph, statusTone, statusWord, viewOf, type Act, type SeatStatus, type BoardCtx, type CardState } from "../kit/crew"
import { entryOf } from "../kit/entry"
import { cycleAxis, dots, previewOf, resolvePets, SLOT_SPECIES, slotOf, SPECIES_BLURB, TEMPERAMENTS, type CatSpecies, type PetSetting, type Pets } from "../kit/pets"
import { AXES } from "../kit/temperament"
import { drop, move, pickUp, place, remove, rotate, startBuild, undo, type Build } from "../kit/home"
import { renderHome } from "../kit/homeart"
import { mailbox } from "../kit/mailbox"
import { soulFor, soulLines, soulNote, useSouls } from "../kit/souls"
import { loadSouls, soulsSignature } from "./souls"
import { overrideFor, trimCustom, useLookOverrides, type LookOverride } from "../kit/looks"
import { ROLE, useRoles, type Role } from "../kit/palette"
import { lifeHeader, lifeRows } from "../kit/life"
import { usageHeader } from "../kit/usage"
import { dialsOf, nextDial, nextPart, PARTS, SLOTS } from "../kit/parts"
import { bringBack, candidateOf, dropPile, hallSignature, loadHall, maybe, pass, saveHall, seatedNames, takenNames, toggleLock, type Hall, type Vocab } from "../kit/hall"
import { hallRows, stepRow } from "./hall"
import { adopt, back as storeBack, candidateOf as storeCandidate, loadStore, pass as storePass, rename, saveStore, shelve, storeNamesTaken, toggleLock as storeToggle, type Store } from "../kit/store"
import { stepStoreRow, storeRows } from "./store"
import { ACCESSORY, BODIES, HAIR_STYLES, HAIR_ROLES, lookOf, rollLook, OUTFIT, paints, shirtOf, SKIN_ROLES, type Accessory, type Look, type Outfit } from "../kit/sprites"
import { NOW_PLAYING_FORMAT, parseNowPlaying } from "../kit/stereo"
import { EMPTY, flagOn, type Agents, type LifeStatus, type CorkNote, type Coworker, type Thread, type ThreadView } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"
import { BAND, OFF_DOOR, OFF_W, WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import { say, handToUqbar, lobbyOf, replies, conversation, speech } from "./talk"
import { studyOf } from "../kit/uqbar"
import * as data from "./data"
import { adder, bind, hints, LEGEND_CHARS, type KeyId } from "./keys"
import { PLAY, toy } from "./sandbox"
import { Editor, wrap } from "./editor"
import { rank } from "./fuzzy"
import { ticketPicks } from "./finder"
import { applyBuild, loadHome } from "./home"
import { inSandbox, loadPets, PETS_PATH, savePets } from "./pets"
import { geometry, hitAt, kittyImage, measureFor, textLayer, type Geometry } from "./paint"
import { READER_KEYS, Reader, type ReaderDeps } from "./reader"
import { timelineRows } from "./timeline"
import { footLines, follow as followSel, offset, type Hint, type Window } from "./pane"
import { badge, cells, enter, ESC, leave, line, mute, out, query, tokenize, type Input, type Seg } from "./term"
import { rows as vtRows, TerminalView, type Target } from "./terminal"
import { centerViewport, clipFrame, panViewport, type Viewport } from "./viewport"
import { parseWhen, showWhen } from "./when"
import { downHeader } from "./down"
import { oneInFlight } from "./flight"
import { earmarkOf, earmarksIn, earmarksOut, freshPosts, handoffFrom } from "../kit/plane"
import { arrange, CREW_GROUPS, CREW_SORTS, next, type Sort } from "./order"

type Mode =
  | { kind: "home" } | { kind: "crew" } | { kind: "notes" } | { kind: "boss" } | { kind: "archive" }
  | { kind: "person"; name: string; from?: Mode } | { kind: "thread"; tid: number; from?: Mode }
  | { kind: "column"; col: number } | { kind: "ticket"; id: number; from?: Mode } | { kind: "epic"; id: number; from?: Mode } | { kind: "calendar" } | { kind: "life" } | { kind: "pages" }
  | { kind: "tray" } | { kind: "triage" } | { kind: "issue"; id: number; from?: Mode } | { kind: "health" } | { kind: "memory" } | { kind: "card" }
  | { kind: "runs"; id: number } | { kind: "run"; id: number; run: number } | { kind: "pet"; who: "cat" | "dog" } | { kind: "arcade" } | { kind: "ideas" } | { kind: "banter" } | { kind: "needs" } | { kind: "decide"; i: number } | { kind: "babel"; page: string[] } | { kind: "entry" }
  | { kind: "build" } | { kind: "settings" } | { kind: "whimsy" } | { kind: "review"; tid: number; from?: Mode }
  | { kind: "look"; name: string; from?: Mode } | { kind: "look-editor"; name: string; view: "front" | "side" | "back"; from?: Mode }
  | { kind: "hall" } | { kind: "hall-pile" } | { kind: "store" }
  | { kind: "help"; from: Mode; title: string; keys: Hint[] }
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
const SAID = join(STATE_DIR, "office-banter") // the room's last lines said, for the banter log
const EARS = join(STATE_DIR, "office-earmarks") // the posts Argos caught, so a restart keeps their dog-ears
const LOOKED = join(STATE_DIR, "margin-looked") // the last focused moment, epoch seconds: older margin notes start already seen
const OPERATOR = process.env.TLON_OPERATOR ?? "andrew"
// the machine's palette, when it hands one in: `{ "role": { "<role>": "#rrggbb", … } }` (or the bare
// map). A link here that the machine repoints on a theme switch is followed within a second.
const PALETTE = process.env.TLON_PALETTE ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/palette.json")
// `--sandbox`: the TUI on a made-up world (tui/sandbox.ts) instead of the server
const SANDBOX = inSandbox()
// the toy keeps its looks, souls and hall in a dir of its own, so a pretend hire never reaches the machine's files
const CONFIG = SANDBOX ? join(tmpdir(), "tlon-sandbox") : join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon")
// per-agent look overrides, same poll shape as PALETTE above
const LOOKS = process.env.TLON_LOOKS ?? join(CONFIG, "looks.json")

// per-coworker SOUL.md files, one `<name>.md` each, polled like LOOKS
const SOULS = process.env.TLON_SOULS ?? join(CONFIG, "souls")

// the hiring hall: current seed + locks + edits and the maybe pile, polled like LOOKS
const HALL = process.env.TLON_HALL ?? join(CONFIG, "hall.json")
// the pet store: species + seed + locks + edits, polled the same way
const STORE = process.env.TLON_STORE ?? join(CONFIG, "store.json")

// the wackiness dial (kit/whimsy.ts): preset + overrides, remembered in the config dir
const OFFICE = process.env.TLON_OFFICE ?? join(CONFIG, "office.json")
let whim: WhimState = loadWhim(OFFICE)
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

const world = SANDBOX ? toy() : null
if (world) data.useFake(world)

let all: Agents = { ...EMPTY, note: "…" }
let ws: number | null = Number(readState(STATE)) || null
// the wide room when the terminal is wide enough for it (`wide` is its width), else the rail room
let wide: number | null = null
const rooms = new Map<number, RailRoom | WideRoom>()
const threads = new Map<number, ThreadView>()
let mode: Mode = { kind: "home" }, picked: number | null = null, sel = 0
let tip = "", status = ""
/** why each card's read came back empty (`data.reading`), by card: a poll still in flight for one card never sets the reason another shows */
const readWhys = new Map<string, string>()
const cardKey = (m: Mode) => JSON.stringify({ ...m, from: undefined })
const waiting = (what: string): Seg => { const why = readWhys.get(cardKey(mode)); return dim(why ? `couldn't read: ${why}` : what) }
/** the header's clickable spans, in 1-based columns, as last drawn */
let headHits: { from: number; to: number; go: () => void }[] = []
// how the list cards are ordered (`s` sort, `g` group): kept across visits
const CREW_GROUP_MODES = [null, ...CREW_GROUPS]
/** the workspace's crews by name, as its seats are on them; `all` is every crew, no crew of its own */
const crewsOf = (w: number | null) => [...new Set((all.shifts ?? []).filter((x) => x.workspace_id === w && x.crew !== "all").map((x) => x.crew))].sort()
const tabLabel = (t: string) => (t === "all" ? "everyone" : t)
let crewTab = "all"
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
let hall: Hall = loadHall(HALL), hallSeen = hallSignature(HALL)
const GRADES = ["junior", "senior", "greybeard"], SPECIALTIES = ["office", "server"]
const hallVocab = (): Vocab => {
  const names = all.archetypes.filter((a) => !a.meta).map((a) => a.name)
  return { archetypes: names.length ? names : ["builder"], grades: GRADES, specialties: SPECIALTIES }
}
const hallCtx = () => ({ taken: takenNames(hall, seatedNames(all), hallVocab()), vocab: hallVocab() })
function hallSet(h: Hall) { hall = h; saveHall(HALL, h); hallSeen = hallSignature(HALL) }
/** a hand edit of hall.json shows up on the next poll; true when it did */
function followHall(): boolean {
  const seen = hallSignature(HALL)
  if (seen === hallSeen) return false
  hallSeen = seen; hall = loadHall(HALL)
  return true
}
async function hallHire() {
  const ctx = hallCtx(), c = candidateOf(hall, ctx)
  if (ctx.taken.includes(c.name)) { status = `${c.name} is already on the bench — pass, or drop it`; return draw() }
  if (world) world.hire(c)
  else {
    if (ws === null) return
    const said = await data.hire(ws, c.name, c.archetype)
    // data.hire's own success line; anything else is the refusal, and nothing is kept
    if (!said.startsWith("hired ")) { status = said; return draw() }
  }
  saveLook(c.name, c.look)
  try { mkdirSync(SOULS, { recursive: true }); writeFileSync(join(SOULS, `${c.name}.md`), c.soul, { flag: "wx" }) } catch { /* theirs already: never overwritten */ }
  soulsSeen = ""
  hallSet(pass(hall, { ...ctx, taken: [...ctx.taken, c.name] }))
  status = `hired ${c.name}`
  void refresh()
  draw()
}
let store: Store = loadStore(STORE), storeSeen = hallSignature(STORE)
const storeTaken = () => storeNamesTaken(all.bench.map((b) => b.name), petsNow ?? resolvePets(loadPets()), store.species)
function storeSet(s: Store) { store = s; saveStore(STORE, s); storeSeen = hallSignature(STORE) }
/** a hand edit of store.json shows up on the next poll; true when it did */
function followStore(): boolean {
  const seen = hallSignature(STORE)
  if (seen === storeSeen) return false
  storeSeen = seen; store = loadStore(STORE)
  return true
}
/** ⏎: adopt the shown candidate into its slot; the occupant leaves by the door, once the operator says y */
function storeAdopt() {
  const taken = storeTaken(), c = storeCandidate(store, taken), slot = slotOf(c.species)
  const file = slot ? adopt(c, slot) : null
  if (!slot || !file) { status = `${c.name} can't be adopted here`; return draw() }
  const old = (petsNow ?? resolvePets(loadPets()))[slot].name
  ask2(slot === "dog" ? `adopt ${c.name} into the dog slot? (the room still draws ${old})` : `${old} leaves by the door. adopt ${c.name}?`, () => {
    savePets(file)
    petsSeen = ""; followPets(); roomChanged = true
    storeSet(storePass(store, [...taken, c.name]))
    status = `adopted ${c.name}`
    draw()
  })
}
// the pet card's draft (Nina's temperament, not yet saved to pets.json) and the preview row's clock
let petDraft: PetSetting | null = null, previewTick = 0
let editBuf: Record<"front" | "side" | "back", string[]> | null = null
let editEntry: Record<"front" | "side" | "back", string[]> | null = null
let editCursor = { x: 0, y: 0 }
let editScroll = 0
let editMirror = true
const blankBuf = () => Array.from({ length: 22 }, () => ".".repeat(12))
let picker: { title: string; q: Editor; items: Pick[]; sel: number } | null = null
let reader: Reader | null = null
/** a thread card's reply box: focused, it takes the keys; unfocused, the card's actions do. Its draft is the thread's, the reader's too */
let cardReply: { tid: number; ed: Editor; focused: boolean } | null = null
/** a thread with an open prompt opens with its box unfocused, so 1–9 answer at once */
const asks = (tid: number) => !!threadOf(tid)?.prompt
const cardBox = () => (!reader && mode.kind === "thread" && cardReply?.tid === mode.tid ? cardReply : null)
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
/** Scharlach's demerit ledger: ticks when a coworker's build goes red (the sheriff's workspace's triage) */
let ledger: Ledger = newLedger()
/** the last banter line each seat said, so the canned fallback doesn't repeat itself */
const recentBanter = new Map<string, string[]>()
/** the office revision this TUI started on: when main's moves past it, R reloads */
let officeRev: string | null | undefined
/** the suggestion box: corkboard ideas the banter wrote in a coworker's voice (never a request), for you to file or throw out */
let ideas: CorkNote[] = []
/** the banter log: the last lines said in the room, oldest first, kept across restarts */
type Said = { at: number; who: string; line: string }
let said: Said[] = (() => { try { return JSON.parse(readState(SAID) ?? "[]") as Said[] } catch { return [] } })()
function heard(turns: { who: string; line: string }[]) {
  // a restart re-reads the server's recent lines: the log already has them
  const fresh = turns.filter((t) => !said.some((x) => x.who === t.who && x.line === t.line))
  said = [...said, ...fresh.map((t) => ({ at: Date.now(), ...t }))].slice(-50)
  writeState(SAID, JSON.stringify(said))
}
let shelf: data.Memory | null = null, tickets: data.BoardTicket[] = [], card: data.WorkspaceCard | null = null, settings: data.Settings | null = null
/** the branch under review, and the notes not yet sent, kept per thread so leaving the screen loses none */
let review: data.Review | null = null
const reviewNotes = new Map<number, data.ReviewNote[]>()
let lifeCard: LifeStatus | null = null
let dumpPages: data.DumpPage[] | null = null
let cal: data.Schedule[] | null = null, board: data.Run[] = []
let trayRead = readState(TRAY)
/** Uqbar's margin notes; `looks` fades each by the time the window was focused after it was first seen */
let notes: Note[] = []
const looks = new Looks(Number(readState(LOOKED)) || 0)
// a terminal that never reports focus is treated as always focused: notes fade from first sight
let focused = true, lit: number | null = null
const stampLooked = () => { looks.lookedAt = Math.floor(Date.now() / 1000); writeState(LOOKED, String(looks.lookedAt)) }

const view = () => viewOf(all, ws)
const crewOn = () => all.workspaces.find((w) => w.id === ws)?.shift ?? ""
/** the crew after the one on, in name order; null with fewer than two crews */
const nextCrew = () => { const cs = crewsOf(ws); return cs.length > 1 ? next(cs, crewOn()) : null }
/** a click on the header's crew: the next crew goes on */
const toggleShift = () => {
  const to = nextCrew()
  if (ws !== null && to) void did(data.shiftSwitch(ws, to))
}
/** the crew on, once the workspace has crews; nothing for one with none */
const shiftHeader = () => (crewsOf(ws).length ? `⇄ ${crewOn()} crew` : null)
const checkLine = /^#(\d+) (?:verify|landing)/
/** the workline the machine's full check runs on now ("#235 verify …"), or null for a session's own check */
const checkingId = (): number | null => { const m = checkLine.exec(all.health?.checks?.running ?? ""); return m ? Number(m[1]) : null }
/** the worklines whose check waits in the queue */
const checkWaitingIds = (): number[] => (all.health?.checks?.waiting ?? []).flatMap((l) => { const m = checkLine.exec(l); return m ? [Number(m[1])] : [] })
/** the header's queues: what is checked and what is merged right now */
function queuesHeader(): string | null {
  const c = all.health?.checks, mq = all.health?.merge_queue ?? []
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
  const cap = settings?.knobs.find((k) => k.key === "max_leaves")?.value
  return { maxLeaves: typeof cap === "number" ? cap : null, needs: needs.flatMap((n) => (n.thread_id ? [n.thread_id] : [])), checking: checkingId(), checkWaiting: checkWaitingIds(), merging: all.health?.merge_queue ?? [] }
}
const room = () => { const k = ws ?? 0; let r = rooms.get(k); if (!r) { rooms.set(k, (r = wide ? new WideRoom(wide) : new RailRoom())); r.setWhimsy(resolveWhim(whim)); if (petsNow) r.setPets(petsNow); if (r instanceof WideRoom) r.setHome(homeNow) } return r }
/** the dial moved: remember it and hand every room the resolved dials */
function setWhim(s: WhimState) {
  whim = s
  saveWhim(OFFICE, s)
  for (const r of rooms.values()) r.setWhimsy(resolveWhim(s))
  changed()
}
const threadOf = (id: number | null) => (id === null ? undefined : all.threads.find((t) => t.id === id))
/** the model a seat gets when it sets none of its own: its archetype's, else the server's default */
const inheritedModel = (archetype: string | null) => all.archetypes.find((x) => x.name === archetype)?.model || "the server's default"
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
// the last poll that answered: a restart's gap polls (ok:false) must not hide what changed across it
let lastOk: Agents = EMPTY, lastOkNeeds: data.Need[] = []
// one refresh in flight and at most one queued: a write's follow-up reads what it wrote (tui/flight.ts)
const refresh = oneInFlight(refreshOnce)
async function refreshOnce() {
  for (const w of dumpSent.keys()) syncDump(w, true)
  // the snapshot lands, and shows, as soon as it comes: the inbox read beside it takes seconds (a git
  // check per stray worktree), and a finder opened meanwhile would list nothing
  const rest = Promise.all([data.needs(), data.settings()])
  all = await data.status()
  if (officeRev === undefined && all.ok) officeRev = all.revs?.office ?? null
  settleWorkspace()
  draw()
  let knobs: data.Settings | null
  ;[needs, knobs] = await rest
  settings = knobs ?? settings
  if (all.ok && lastOk.ok) tellNews(lastOk, lastOkNeeds)
  if (all.ok) { lastOk = all; lastOkNeeds = needs }
  const tid = openThread()
  await Promise.all([tid !== null ? loadThread(tid) : null, reader ? reader.reload() : null, loadCard(), loadFeed(), loadMargin()])
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
  if (!all.ok) return
  const sws = all.bench.find((c) => c.archetype === "sheriff")?.workspace_id
  if (sws == null) return
  const count = all.triage[String(sws)] ?? 0
  const t = count > 0 ? await data.triage(sws) : null
  if (count > 0 && !t) return
  const before = new Map(ledger.demerits)
  ledger = tickFromTriage(ledger, count, t?.failed_thread_ids ?? t?.failed_checks.shown.map((s) => s.thread_id) ?? [], all.threads)
  // rimworld: a red build sours that coworker's afternoon — room-local, the room's own reading of what it already saw
  for (const [who, n] of ledger.demerits) if (n > (before.get(who) ?? 0)) for (const r of rooms.values()) r.sourMood(who)
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
  for (const kind of arrivals(before, all, beforeNeeds, needs)) room().ring(kind)
  releaseOnTv(before, all)
}
/** a cut puts Uqbar's entry on the TV; the next snapshot that holds the same sha ends it */
function releaseOnTv(before: Agents, after: Agents) {
  if (!before.ok || !after.ok || !after.release) return
  for (const r of rooms.values()) {
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
/** the feed rows already flown as aeroplanes */
const flown = new Set<string>()
async function loadMargin() { notes = ws === null ? [] : await data.margin(ws) }
/** the posts whose aeroplane Argos caught, by `earmarkOf`: the thread shows them dog-eared */
const earmarked = earmarksIn(readState(EARS))
async function loadFeed() {
  if (ws === null) return
  const first = !feed.length
  feed = (await data.activity(ws)) ?? feed
  const v = view(), r = room()
  for (const x of freshPosts(feed, flown, first)) {
    if (r instanceof WideRoom && r.fly(x.thread_id!, v, handoffFrom(v.visits, v, x.thread_id!, Date.now()))) {
      earmarked.add(earmarkOf(x.thread_id!, x.at, x.who))
      writeState(EARS, earmarksOut(earmarked))
    }
  }
  // a first run starts with the tray read, not with everything that ever happened in it
  if (!trayRead && feed[0]) { trayRead = feed[0].at; writeState(TRAY, trayRead) }
}
// the office's small talk: each line the server's banter wrote, once, as a balloon over its speaker
const seenLines = new Set<string>()
async function chatter() {
  if (ws === null) return
  room().hear(await data.pets(ws, room().petProfile()))
  const here = ws
  const dials = resolveWhim(whim), banter = dials.banter
  // generated visitors, puns and reactions reach the room only past `curated`; the room ignores a pool it is not given
  room().setToys(dials.weirdness === "curated" ? null : await data.toys(here))
  // two together in the room: with souls on the server writes what they say now (from their souls), said turn by turn;
  // with them off, in --sandbox, or wherever the server wrote nothing, each says a canned line in their own voice
  room().onTogether = (situation, a, b) => !banter ? undefined : void (dials.souls ? data.talk(here, situation, a, b) : Promise.resolve([])).then((turns) => {
    const said = turns.length ? turns : [a, b].map((who) => {
      const recent = recentBanter.get(who) ?? []
      const line = seatLine(who, recent)
      recentBanter.set(who, [line, ...recent].slice(0, 8))
      return { who, line }
    })
    room().converse(said); heard(said); changed()
  })
  cork = await data.corkboard(ws)
  room().pinboard(cork)
  ideas = await data.suggestions(ws)
  room().suggestionBox(ideas)
  // a conversation the server wrote arrives as lines sharing one `at`: said as one, turn by turn
  const convos = new Map<number, { who: string; line: string }[]>()
  for (const b of await data.banter(ws)) {
    const k = `${b.at} ${b.agent} ${b.line}`
    if (seenLines.has(k)) continue
    seenLines.add(k)
    convos.set(b.at, [...(convos.get(b.at) ?? []), { who: b.agent, line: b.line }])
  }
  if (banter) for (const turns of convos.values()) { room().converse(turns); heard(turns); changed() }
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
  const key = cardKey(mode)
  const why = await data.reading(() => readCard(w))
  if (why) readWhys.set(key, why); else readWhys.delete(key)
}
async function readCard(w: number) {
  switch (mode.kind) {
    case "archive": archived = await data.archive(w); break
    case "triage": case "issue": stuck = await data.triage(w); break
    case "health": rack = await data.health(); break
    case "memory": shelf = await data.memory(w); break
    case "ticket": case "epic": case "column": tickets = (await data.board(w)) ?? tickets; break
    case "card": card = await data.workspaceCard(w); break
    case "settings": settings = await data.settings(); break
    case "review": review = await data.review(mode.tid); break
    case "calendar": cal = await data.schedules(w); break
    case "life": lifeCard = (await data.life(w)) ?? lifeCard; break
    case "pages": dumpPages = await data.dumpPages(w); break
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
  if ((m.kind === "person" || m.kind === "thread" || m.kind === "look" || m.kind === "review" || m.kind === "issue") && m.from === undefined && mode.kind !== "home" && mode.kind !== "help" && mode.kind !== m.kind) m = { ...m, from: mode }
  status = ""; readWhys.delete(cardKey(m)); mode = m; sel = 0; scroll = m.kind === "thread" || m.kind === "person" ? Infinity : 0; confirm = null; picker = null; snapSel = true
  if (m.kind === "thread") { picked = m.tid; cardReply = { tid: m.tid, ed: cardReply?.tid === m.tid ? cardReply.ed : new Editor(), focused: !asks(m.tid) } }
  if (m.kind === "person") picked = crewOf(view()).find((c) => c.name === m.name)?.thread ?? null
  if (m.kind === "pet" && m.who === "cat") { petDraft = structuredClone((petsNow ?? resolvePets(loadPets())).cat); previewTick = 0 }
  if (m.kind === "look") lookDraft = { ...lookOf(m.name), ...overrideFor(m.name) }
  const tid = openThread()
  void Promise.all([tid !== null ? loadThread(tid) : null, loadCard()]).then(draw)
  draw()
}
/** Esc: a card back to the card it was opened from, else home; home to nothing picked; `all` drops both at once */
function back(everything = false) {
  const from = !everything && mode.kind !== "help" && "from" in mode ? mode.from : undefined
  status = ""
  if (everything || mode.kind === "home") picked = null
  mode = from ?? { kind: "home" }; sel = 0; scroll = 0; confirm = null; picker = null; lookDraft = null; petDraft = null
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
    case "needs": return inbox()
    case "rack": return open({ kind: "health" })
    case "dog": { const r = room(); if (r instanceof WideRoom) r.patDog(); changed(); return open({ kind: "pet", who: "dog" }) }
    case "tv": { const r = room(); if (r instanceof WideRoom) { r.channel(); changed(); draw() } return }
    case "arcade": return open({ kind: "arcade" })
    case "ideas": return open({ kind: "ideas" })
    case "weather": status = all.weather ? `outside: ${all.weather.desc.toLowerCase()}${all.weather.temp_c === null ? "" : `, ${all.weather.temp_c}°C`}` : "no word on the weather"; return draw()
  }
}

// ── writing: the inputs ─────────────────────────────────────────────────────────────────────────
/** what an input held when ctrl+] left it, by its label, there again when it is asked again */
const banked = new Map<string, string>()
function ask(label: string, submit: Prompt["submit"], opts: { multiline?: boolean; text?: string; cycles?: Cycle[] } = {}) {
  const held = banked.get(label)
  banked.delete(label)
  input = { label, ed: new Editor(held ?? opts.text ?? "", !!opts.multiline), submit, cycles: opts.cycles, focus: 0 }
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
  // every thread, not the workspace's view: uqbar's study may live on another workspace
  const label = to ? `say to ${to}` : "say to the office"
  ask(label, (s) => {
    const sent = say(all.threads, w, to, s)
    // a post that did not go keeps its words: `'` brings them back
    void sent.then((line) => { if (s.trim() && !data.landed(line)) banked.set(label, s) })
    void did(sent)
  }, { multiline: true })
}
function reply(tid: number) {
  const box = cardBox()
  if (box?.tid === tid) { box.focused = true; return draw() }
  openReader(tid)
}
/** a key while a thread card's reply box has focus: Enter sends, Esc leaves the box (the card stays) */
function boxKey(box: NonNullable<typeof cardReply>, k: string) {
  if (k === "esc") { box.focused = false; return draw() }
  if (k === "enter") {
    if (box.ed.empty) return
    const body = box.ed.text
    box.ed = new Editor(); scroll = Infinity
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
  openReader(id)
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
  const toyVerbs: [string, () => void][] = world ? [["cut a release (the toy: Uqbar's entry on the TV)", () => { world.cut(); status = "a cut: pizza at the door, the entry on the TV"; void refresh() }]] : []
  for (const [label, run] of [...VERBS, ...toyVerbs]) picks.push({ segs: [{ s: "do ", fg: ROLE.inactive }, { s: label, fg: ROLE.prose }], text: label, run })
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
  const after = () => { if (mode.kind === "issue" && !stuck?.blockers.shown.some((x) => x.issue_id === s.issue_id)) back(); draw() }
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
/** what can be done about one waiting item — the inbox's list and its one-at-a-time card share these */
function needActions(n: data.Need): Action[] {
  const tid = n.thread_id ?? null
  const after = () => void refresh()
  const acts: Action[] = [
    ...(n.kind === "gate" && tid ? [{ ...bind("need.A.gate"), run: () => void did(data.approve(tid)).then(after) }] : []),
    ...(n.kind === "dialog" && n.ref ? (n.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void did(data.answer(n.ref!, o.key)).then(after) })) : []),
    ...(n.kind === "ask" && n.ref ? (n.options ?? []).slice(0, 9).map((o): Action => ({ key: o.key, label: o.label, run: () => void did(data.answer(n.ref!, o.key)).then(after) })) : []),
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
function inbox() { open(needs.length ? { kind: "decide", i: 0 } : { kind: "needs" }) }
/** a need's one-line name: what kind, and where */
const NEED_KIND: Record<data.Need["kind"], string> = { gate: "gate", question: "question", dialog: "dialog", ask: "asks you", verify_failed: "verify red", stalled: "stalled", mention: "mentioned you", rollout: "rollout", seats: "waits for a seat", job_failed: "job failed", stranded: "stranded work", issue: "issue", publish_failed: "not on GitHub", release_failed: "cut failed", pr_blocked: "PR not merging", quota: "out of quota", no_seat: "no seat" }
const NEED_TONE: Record<data.Need["kind"], string> = { gate: ROLE.attention, question: ROLE.key, dialog: ROLE.alarm, ask: ROLE.key, verify_failed: ROLE.alarm, stalled: ROLE.attention, mention: ROLE.body, rollout: ROLE.live, seats: ROLE.attention, job_failed: ROLE.alarm, stranded: ROLE.attention, issue: ROLE.alarm, publish_failed: ROLE.alarm, release_failed: ROLE.alarm, pr_blocked: ROLE.alarm, quota: ROLE.attention, no_seat: ROLE.attention }
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
  ["Uqbar's entry — the office as a page", () => open({ kind: "entry" })],
]

// ── the reader: a thread full-screen ────────────────────────────────────────────────────────────
function openReader(tid: number, extra: Partial<ReaderDeps> = {}, focus = !asks(tid)) {
  picked = tid
  reader = new Reader(tid, { load: (before) => (before ? data.page(tid, before) : data.thread(tid)), send: (body) => data.post(tid, body), operator: OPERATOR, redraw: () => draw(), dogeared: (m) => earmarked.has(earmarkOf(tid, m.at, m.author)), ...extra }, focus, cardReply?.tid === tid ? cardReply.ed.text : "")
  if (cardReply?.tid === tid) cardReply = null
  const v = threads.get(tid)
  if (v) reader.take(v)
  void reader.reload().then(draw)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
  draw()
}
/** the conversation with `name`: the lobby filtered to them and the operator's words to them; a reply goes to them */
function openConversation(name: string) {
  const lobby = lobbyOf(view().threads, ws)
  if (lobby === null) { status = "no front desk in this workspace"; return draw() }
  openReader(lobby, {
    keep: (ms) => conversation(ms, name, OPERATOR),
    heading: `conversation with ${name}`,
    send: (body) => data.post(lobby, speech(name, body) ?? body),
  })
}
/** the reader's draft goes back to the thread's box, so its card or the next reader starts from it */
function bankReader() {
  const held = reader?.held()
  if (reader && held) cardReply = { tid: reader.tid, ed: new Editor(held), focused: true }
}
function closeReader() {
  bankReader()
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
  const prompt = th?.prompt
  const answers = (prompt?.options ?? []).slice(0, 9).map((o, i): Action => ({ key: String(i + 1), label: `answer: ${o.label}`, run: () => void did(data.answer(prompt!.id, o.key)) }))
  return [
    ...answers,
    ...(inReader ? [] : [{ ...bind("thread.v"), run: () => openReader(tid) }]),
    { ...bind("thread.r"), run: () => reply(tid) },
    ...(studyOf(all.threads, ws) !== null && studyOf(all.threads, ws) !== tid ? [{ ...bind("thread.u"), run: () => void did(handToUqbar(all.threads, ws, tid)) }] : []),
    ...(th?.awaiting && th.stage ? [{ ...bind("thread.A", `approve: ${th.awaiting}`), run: () => void did(data.approve(tid)) }] : []),
    ...(th?.stage ? [{ ...bind("thread.>"), run: () => void did(data.advance(tid)) }] : []),
    ...(th && cardState(view(), th, boardCtx())?.atCap ? [{ ...bind("thread.S"), run: () => { if (reader) closeReader(); open({ kind: "settings" }) } }] : []),
    { ...bind("thread.t"), run: () => void zoomInto(tid) },
    { ...bind("thread.g"), run: () => void zoomGit(tid) },
    ...(th?.stage ? [{ ...bind("thread.d"), run: () => void pickDoc(tid) }, { ...bind("thread.R"), run: () => { if (reader) closeReader(); open({ kind: "review", tid }) } }] : []),
    {
      ...bind("thread.h"), run: () => {
        const bench = view().bench
        find(`HAND #${tid} OFF TO`, bench.map((c) => ({ segs: [{ s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}${c.name === th?.lead ? " · leads it now" : ""}`, fg: ROLE.inactive }], text: c.name, run: () => { picker = null; void did(data.handOff(tid, c.name)) } })))
      },
    },
    {
      ...bind("thread.P"), run: () => {
        find(`MOVE #${tid} TO PROJECT`, view().projects.map((p) => ({ segs: [{ s: p.name, fg: ROLE.prose }], text: p.name, run: () => { picker = null; void did(data.move(tid, p.id)) } })))
      },
    },
    { ...bind("thread.x"), run: () => ask2(`close #${tid} as done`, () => did(data.closeThread(tid))) },
    { ...bind("thread.D"), run: () => ask2(`delete #${tid} for good (its worktree goes too, if it loses nothing)`, () => { if (reader) closeReader(); back(); void did(data.deleteThread(tid)) }) },
  ]
}

/** the verbs on a seated coworker: their model, ask/allow, a clean slate, letting them go */
function seatActions(b: Coworker | undefined): Action[] {
  const w = ws, a = view()
  if (!b || w === null) return []
  return [
    {
      ...bind("seat.M"), run: () => {
        const models = [{ label: `the archetype's (${inheritedModel(b.archetype)})`, value: "inherit" }, ...a.models.map((m) => ({ label: `${m.key}  ${m.thinking} · ${m.harness}`, value: m.key }))]
        find(`${b.name.toUpperCase()}'S MODEL`, models.map((m) => ({ segs: [plain(m.label)], text: m.label, run: () => { picker = null; void did(data.retarget(w, b.agent_id, { model: m.value })) } })))
      },
    },
    { ...bind("seat.y", b.ask === "allow" ? "ask before acting" : "allow without asking"), run: () => void did(data.retarget(w, b.agent_id, { ask: b.ask === "allow" ? "ask" : "allow" })) },
    {
      ...bind("seat.E"), run: () => {
        const p = b.persona
        const items: { label: string; run: () => void }[] = [
          p
            ? { label: "draw a new one (reroll)", run: () => ask2(`reroll ${b.name}'s persona — the hand edits go`, () => { status = "drawing a new one…"; draw(); void did(data.persona(w, b.agent_id, true)) }) }
            : { label: "make one", run: () => { status = "drawing one…"; draw(); void did(data.persona(w, b.agent_id, false)) } },
          ...(p ? [
            { label: "edit the voice", run: () => ask(`${b.name}'s voice`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { voice: s.trim() })) }, { text: p.voice }) },
            { label: "edit the backstory", run: () => ask(`${b.name}'s backstory`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { backstory: s.trim() })) }, { text: p.backstory }) },
            ...(["desk_object", "hobby", "catchphrase", "pet_peeve"] as const).map((k) => ({ label: `edit ${k.replace("_", " ")}`, run: () => ask(`${b.name}'s ${k.replace("_", " ")}`, (s) => { if (s.trim()) void did(data.personaEdit(w, b.agent_id, { quirks: { [k]: s.trim() } })) }, { text: p.quirks[k] }) })),
          ] : []),
        ]
        find(`${b.name.toUpperCase()}'S PERSONA`, items.map((i) => ({ segs: [plain(i.label)], text: i.label, run: () => { picker = null; i.run() } })))
      },
    },
    { ...bind("seat.C"), run: () => ask2(`clear ${b.name}'s context — their session ends, they start fresh when next needed`, () => did(data.clearContext(w, b.agent_id, b.name))) },
    { ...bind("seat.-"), run: () => ask2(`let ${b.name} go from ${wsName()} (the agent itself stays)`, () => did(data.unseat(b.seat_id, b.name))) },
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
    const r = Bun.spawnSync(["playerctl", "metadata", "--format", NOW_PLAYING_FORMAT])
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
    { ...bind("live.enter"), run: () => void zoomInto(tid) },
    { ...bind("live.c", talkView.has(tid) ? "their activity" : "the conversation"), run: () => { if (!talkView.delete(tid)) talkView.add(tid); draw() } },
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
        ? STAGE_RING.flatMap((st, i): Seg[] => [...(i ? [dim(" ▸ ")] : []), i === cur ? { s: ` ${st === "merged" && th.landing ? "landing" : st} `, fg: ROLE.ground, bg: th.awaiting ? ROLE.attention : ROLE.key, bold: true } : { s: st, fg: i < cur ? ROLE.live : ROLE.inactive }])
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

const back1: Action = { ...bind("back.esc"), run: () => { back(); roomChanged = true; draw() } }
const pick = <T,>(xs: T[], i: number) => (i >= 0 ? xs[i] : undefined)

/** the card the pane shows: its title, its rows (the left, j/k + enter when any open), its actions (the right, by key) */
function detail(): { title: string; rows: Row[]; actions: Action[]; tint?: string } {
  const a = view(), w = ws
  switch (mode.kind) {
    case "home": {
      const waiting = a.threads.filter(needsYou)
      const actions: Action[] = [
        { ...bind("home./"), run: () => void finder() }, { ...bind("home.i"), run: inbox },
        { ...bind("home.n"), run: newThread }, { ...bind("home.N"), run: newTicket },
        { ...bind("home.c"), run: () => open({ kind: "crew" }) }, { ...bind("home.t"), run: () => open({ kind: "column", col: 0 }) },
        { ...bind("home.w"), run: () => open({ kind: "tray" }) }, { ...bind("home.!"), run: () => open({ kind: "triage" }) },
        { ...bind("home.a"), run: () => open({ kind: "calendar" }) }, { ...bind("home.o"), run: () => open({ kind: "notes" }) },
        { ...bind("home.b"), run: () => open({ kind: "memory" }) }, { ...bind("home.H"), run: () => open({ kind: "health" }) },
        ...(all.life?.[String(w)] ? [{ ...bind("home.L"), run: () => open({ kind: "life" }) }] : []),
        ...(flagOn(all, "build_mode") ? [{ ...bind("home.B"), run: () => open({ kind: "build" }) }] : []),
        { ...bind("home.f"), run: () => open({ kind: "archive" }) }, { ...bind("home.W"), run: () => open({ kind: "boss" }) },
        { ...bind("home.S"), run: () => open({ kind: "settings" }) },
        { ...bind("home.h"), run: () => open({ kind: "hall" }) },
        { ...bind("home.P"), run: () => open({ kind: "store" }) },
        { ...bind("home.q"), run: quit },
      ]
      if (!waiting.length) return { title: "HOME", rows: [{ segs: [dim("nothing waits on you. click someone — or Nina, or Argos — a sticky or the crew board;")] }, { segs: [dim("tab walks the crew, [ ] the workspaces.")] }], actions }
      return { title: `WAITING ON YOU · ${waiting.length}`, rows: waiting.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), pink(`  ${t.prompt?.summary ?? `awaits ${t.awaiting}`}`)], open: () => openReader(t.id) })), actions }
    }
    case "crew": {
      // tabs: each crew, then everyone; the crew on has the live status
      const seats = (all.shifts ?? []).filter((x) => x.workspace_id === ws)
      const crews = crewsOf(ws), tabsOf = [...crews, "all"], on = crewOn(), other = nextCrew()
      if (!tabsOf.includes(crewTab)) crewTab = "all"
      const live = crewOf(a)
      const inTab = (name: string) => crewTab === "all" || seats.find((x) => x.name === name)?.crew === crewTab
      const crew = [...live, ...seats.filter((x) => !live.some((c) => c.name === x.name)).map((x) => ({ name: x.name, archetype: x.archetype, status: "off" as SeatStatus, thread: null, title: "", manager: false, lead: false }))].filter((c) => inTab(c.name))
      const shiftOf = (name: string) => seats.find((x) => x.name === name)?.crew
      const tabs: Seg[] = tabsOf.flatMap((t) => [t === crewTab ? { s: ` ${tabLabel(t)} `, fg: ROLE.ground, bg: ROLE.key, bold: true } : dim(` ${tabLabel(t)} `), plain(" ")])
      const paused = all.pause === "pencils_down" || all.pause === "lights_out"
      const rows: Row[] = [{ segs: [...tabs, dim(crews.length ? `   the ${on} crew is on` : "   no crews yet: c puts a seat on one"),
        ...(paused ? badge({ s: all.pause === "lights_out" ? "  ◼ lights out " : "  ✎ pencils down ", fg: ROLE.ground, bg: ROLE.attention, bold: true }) : [dim("   at work")])] }]
      for (const g of arrange(crew as any, crewSort.cmp, crewGroup)) {
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
      const chosen = a.bench.find((x) => x.name === rows[sel]?.ref), seat = seats.find((x) => x.name === rows[sel]?.ref)
      const seatTo = seat ? next(tabsOf, seat.crew) : "all"
      const newCrew = () => { if (seat) ask(`put ${seat.name} on a new crew — its name (lowercase, - and _)`, (s) => { if (s.trim()) void did(data.seatShift(seat.seat_id, seat.name, s.trim())) }) }
      return {
        title: `CREW · ${crew.length} · ${tabLabel(crewTab)} · by ${crewGroup ? `${crewGroup.name}, ` : ""}${crewSort.name}`,
        rows,
        actions: [{ ...bind("crew.v", `tab: ${tabLabel(next(tabsOf, crewTab))}`), run: () => { crewTab = next(tabsOf, crewTab); sel = 0; draw() } },
          ...(seat ? [{ ...bind("crew.c", `${seat.name} on ${seatTo === "all" ? "every crew" : seatTo}`), run: () => void did(data.seatShift(seat.seat_id, seat.name, seatTo)) }, { ...bind("crew.n"), run: newCrew }] : []),
          ...(other ? [{ ...bind("crew.S", `put the ${other} crew on`), run: () => { if (ws !== null) void did(data.shiftSwitch(ws, other)) } }] : []),
          { ...bind("crew.+"), run: hire },
          paused ? { ...bind("crew.P.paused"), run: () => void did(data.pause("back_to_work")) }
            : { ...bind("crew.P.running"), run: () => void did(data.pause("pencils_down")) },
          ...(all.pause !== "lights_out" ? [{ ...bind("crew.L"), run: () => ask2("lights out — pause verify and landing, interrupt every pane", () => void did(data.pause("lights_out"))) }] : []),
          { ...bind("crew.s", `sort: ${crewSort.name} → ${next(CREW_SORTS, crewSort).name}`), run: () => resort(() => { crewSort = next(CREW_SORTS, crewSort) }) },
          { ...bind("crew.g", `group: ${crewGroup?.name ?? "none"} → ${next(CREW_GROUP_MODES, crewGroup)?.name ?? "none"}`), run: () => resort(() => { crewGroup = next(CREW_GROUP_MODES, crewGroup) }) },
          ...seatActions(chosen), back1],
      }
    }
    case "person": {
      const name = mode.name
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
      const soulRows: Row[] = soul ? [{ segs: [dim("soul")] }, ...soulLines(soul).flatMap(({ head: h, text }) => [...(h ? [{ segs: [key(h)] }] : []), ...(soulNote(h) ? [{ segs: [dim(soulNote(h)!)] }] : []), ...text.split("\n").map((l) => ({ segs: [plain(l)] }))])] : []
      const rows: Row[] = [...(c.thread === null ? [head, { segs: [dim("on the bench")] }] : [head, ...threadRows(threadOf(c.thread), c.thread, 1)]), ...soulRows]
      for (const l of personaLines(b?.persona, Math.max(20, cols() - 40))) rows.push({ segs: [dim(l)] })
      // Scharlach's desk dressing: the nameplate (tertius never agreed to the second part), the mug
      // he bought himself, and the demerit ledger he keeps on the rest of the office
      if (name === SHERIFF) {
        rows.push({ segs: [dim("nameplate: "), plain(NAMEPLATE)] }, { segs: [dim("mug: "), plain(MUG)] }, ...ledgerLines(ledger, a.bench).map((l) => ({ segs: [dim(l)] })))
      }
      return { title: name.toUpperCase(), rows, tint: shirtOf(c.archetype), actions: [{ ...bind("person.m"), run: () => talk(name) }, { ...bind("person.v"), run: () => openConversation(name) }, ...(c.thread === null ? [] : [{ ...bind("person.w", `read #${c.thread}`), run: () => openReader(c.thread!) }, ...liveActions(c.thread), ...threadActions(c.thread).filter((x) => x.key !== "v")]), ...seatActions(b), { ...bind("person.l"), run: () => open({ kind: "look", name }) }, back1] }
    }
    case "thread": {
      const tid = mode.tid
      const th = threadOf(tid)
      return { title: `THREAD #${tid}${th?.stage ? ` · workline ${th.stage}` : ""}`, rows: threadRows(th, tid), tint: th?.awaiting || th?.prompt ? ROLE.attention : th?.lead ? authorColor(th.lead) : ROLE.key, actions: [...liveActions(tid), ...threadActions(tid), back1] }
    }
    case "column": {
      const col = boardColumns(a, boardCtx())[mode.col]!, items = arrange(col.items, colSort.cmp, null)[0]!.items
      const it = pick(items, sel)
      const reorder = (dir: "up" | "down"): Action => ({ ...bind(dir === "up" ? "column.K" : "column.J", `move ${dir}`), run: () => { if (it?.act.kind === "ticket") void did(data.ticketReorder(it.act.id, dir)).then(() => { sel = Math.max(0, Math.min(sel + (dir === "up" ? -1 : 1), items.length - 1)); draw() }) } })
      return {
        title: `${col.name} · ${items.length}${colSort.name === "board" ? "" : ` · by ${colSort.name}`}`,
        rows: items.map((x) => {
          const blocked = x.act.kind === "ticket" && (tickets.find((t) => t.id === (x.act as { id: number }).id)?.blocked_by.length ?? 0) > 0
          return {
            segs: [...(x.state ? [stateSeg(x.state)] : []), key(x.act.kind === "ticket" || x.act.kind === "epic" ? `#${x.act.id} ` : x.act.kind === "thread" ? `#${x.act.tid} ` : ""), plain(x.title), dim(`  ${x.stage}${x.who ? ` · ${x.who}` : ""}`),
              ...(x.state ? [{ s: `  ${x.state.why}`, fg: x.state.kind === "needs" ? ROLE.attention : ROLE.inactive }] : x.asks ? [pink("  waiting on you")] : []), ...(blocked ? [pink("  ⊘ blocked")] : [])],
            open: () => x.act.kind === "ticket" || x.act.kind === "epic" ? open({ ...x.act, from: mode }) : act(x.act), ref: JSON.stringify(x.act),
          }
        }),
        actions: [
          ...(mode.col === 0 ? [{ ...bind("column.n"), run: newTicket }, ...(colSort.name === "board" ? [reorder("up"), reorder("down")] : [])] : []),
          { ...bind("column.s", `sort: ${colSort.name} → ${next(COL_SORTS, colSort).name}`), run: () => resort(() => { colSort = next(COL_SORTS, colSort) }) },
          { ...bind("column.right"), run: () => open({ kind: "column", col: ((mode as { col: number }).col + 1) % COLS.length }) },
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
          ...kids.map((k) => ({ segs: [key(`#${k.id} `), plain(k.title), dim(`  ${k.routed ? "with the manager" : "ticket"}`)], open: () => open({ kind: "ticket", id: k.id, from: mode }), ref: JSON.stringify({ kind: "ticket", id: k.id }) }))],
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
          { ...bind("ticket.S"), run: () => void did(data.ticketStart(id)) },
          { ...bind("ticket.s"), run: () => void did(data.ticketRoute(id)) },
          { ...bind("ticket.e"), run: () => ask(`ticket #${id} title`, (s) => { if (s.trim()) did(data.ticketPatch(id, { title: s.trim() })) }, { text: tk.title }) },
          {
            ...bind("ticket.b"), run: () => {
              const others = tickets.filter((t) => t.id !== id && t.status !== "done")
              find(`#${id} IS BLOCKED BY`, others.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), dim(`  ${t.status}`)], text: `#${t.id} ${t.title}`, run: () => { picker = null; void did(data.ticketBlock(id, t.id)) } })))
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
      const booked = new Set((cal ?? []).filter((s) => s.enabled).flatMap((s) => s.days))
      const rows: Row[] = [{ segs: [dim("  Su  Mo  Tu  We  Th  Fr  Sa")] }]
      let week: Seg[] = [plain("    ".repeat(first))]
      for (let d = 1; d <= days; d++) {
        const cell = String(d).padStart(3) + (booked.has(d) ? "•" : " ")
        week.push(d === now.getDate() ? { s: cell, fg: ROLE.attention, bold: true } : booked.has(d) ? key(cell) : d < now.getDate() ? dim(cell) : plain(cell))
        if ((first + d) % 7 === 0 || d === days) { rows.push({ segs: week }); week = [] }
      }
      if (!cal) rows.push({ segs: [waiting("reading the schedule…")] })
      else if (!cal.length) rows.push({ segs: [dim("nothing scheduled yet")] })
      else {
        rows.push({ segs: [key(`SCHEDULED · ${cal.length}`)] })
        for (const s of cal) rows.push({ segs: scheduleSegs(s), open: () => open({ kind: "runs", id: s.id }), ref: s })
      }
      const s = rows[sel]?.ref as data.Schedule | undefined
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
      const s = lifeCard
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
      const rows: Row[] = !dumpPages ? [{ segs: [waiting("turning back the pages…")] }]
        : !dumpPages.length ? [{ segs: [dim("no earlier pages yet: every save keeps the one it replaced")] }]
        : dumpPages.map((p) => ({ segs: [dim(`${stamp(p.at)}  `), plain(data.lines(p.lines)), dim(`  ${p.first}`)], open: () => void readPage(p.id), ref: p }))
      const p = rows[sel]?.ref as data.DumpPage | undefined
      const up: Action = { ...bind("pages.esc"), run: () => open({ kind: "life" }) }
      return {
        title: "THE DUMP · EARLIER PAGES", rows,
        actions: [...(p ? [{ ...bind("pages.enter"), run: () => void readPage(p.id) }, { ...bind("pages.R"), run: () => ask2(`put back the ${stamp(p.at)} page (today's is kept as an earlier page)`, () => void restorePage(p.id)) }] : []), up],
      }
    }
    case "runs": {
      const id = mode.id, s = cal?.find((x) => x.id === id)
      const rows: Row[] = board.map((r) => ({
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
      const { id, run } = mode
      const r = board.find((x) => x.id === run)
      const up: Action = { ...bind("run.esc"), run: () => open({ kind: "runs", id }) }
      if (!r) return { title: "RUN", rows: [{ segs: [dim("gone")] }], actions: [up] }
      const rows: Row[] = [{ segs: [runGlyph(r), dim(` started ${stamp(r.started_at)}${r.finished_at ? `, finished ${stamp(r.finished_at)}` : ", still running"}`), ...(r.thread_id ? [key(`  → #${r.thread_id}`)] : [])] }]
      for (const l of wrap(r.output ?? "(no output)", cols() - 40)) rows.push({ segs: [plain(l)] })
      return { title: `RUN #${r.id} · ${r.status}${r.exit === null ? "" : ` · exit ${r.exit}`}`, rows, actions: [...(r.thread_id ? [{ ...bind("run.t"), run: () => openReader(r.thread_id!) }] : []), up] }
    }
    case "archive": {
      if (!archived) return { title: "FILING CABINET", rows: [{ segs: [waiting("opening the drawers…")] }], actions: [back1] }
      const day = (s: string | null) => (s ? s.slice(0, 10) : "")
      const rows: Row[] = [{ segs: [key(`TICKETS DONE · ${archived.tickets.length}`)] }]
      for (const t of archived.tickets) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${day(t.closed_at)}`)] })
      rows.push({ segs: [key(`THREADS CLOSED · ${archived.threads.length}`)] })
      for (const t of archived.threads) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${t.stage ?? ""} ${day(t.at)}`)], open: () => openReader(t.id) })
      return { title: "FILING CABINET", rows, actions: [back1] }
    }
    case "notes": {
      const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const rows: Row[] = a.notes.map((n) => ({ segs: [who(n.author), plain(n.body.replace(/\s+/g, " "))] }))
      // the crew's chatter, apart from the notes they work from (their suggestions go in the box)
      if (cork.length) rows.push({ segs: [key(`CORKBOARD · ${cork.length} — the crew's notes to each other`)] }, ...cork.map((n): Row => ({ segs: [dim(`${n.kind.padEnd(10)} `), who(n.author), plain(n.body), dim(n.re ? `  (re #${n.re})` : "")], ref: n })))
      return { title: `NOTES · ${a.notes.length}`, rows, actions: [{ ...bind("notes.n"), run: newNote }, back1] }
    }
    case "tray": {
      const rows = arrange(feed, traySort.cmp, null)[0]!.items.map((x): Row => ({
        segs: [dim(ago(x.at).padStart(4) + " "), x.thread_id ? key(`#${x.thread_id} `) : dim(""), { s: `${x.who ?? ""} ${KIND[x.kind] ?? x.kind.replace(/_/g, " ")} `, fg: x.kind === "issue" || x.kind === "check_failed" ? ROLE.alarm : x.kind === "question" ? ROLE.attention : ROLE.inactive }, plain(x.text.replace(/\s+/g, " "))],
        open: x.thread_id ? () => openReader(x.thread_id!) : undefined, ref: `${x.at}${x.kind}${x.text}`,
      }))
      return {
        title: `IN-TRAY · ${wsName()}${traySort.name === "newest" ? "" : ` · by ${traySort.name}`}`, rows: rows.length ? rows : [{ segs: [dim("nothing yet")] }],
        actions: [{ ...bind("tray.s", `sort: ${traySort.name} → ${next(TRAY_SORTS, traySort).name}`), run: () => resort(() => { traySort = next(TRAY_SORTS, traySort) }) }, back1],
      }
    }
    case "triage": {
      if (!stuck) return { title: "TRIAGE", rows: [{ segs: [waiting("looking…")] }], actions: [back1] }
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
      section("BLOCKERS — open issues", stuck.blockers, "blocker"); section("FAILED CHECKS", stuck.failed_checks, "check")
      if (stuck.failed_checks.shown.length) rows.push({ segs: [dim("  y re-runs verify, only for a thread at its verify stage")] })
      section("NOBODY LEADS", stuck.unled, "unled")
      // the cursor lands on the first row only after this build, so its actions are read from where it will be
      const at = rows[rows[sel]?.open ? sel : rows.findIndex((r) => r.open)]?.ref as { s: data.Stuck; kind: StuckKind } | undefined
      return {
        title: `TRIAGE · ${stuck.count} known problems · the sheriff's`, rows: rows.length ? rows : [{ segs: [dim("nothing is stuck. the beacon is dark.")] }],
        actions: [...(at ? stuckActions(at.s, at.kind) : []), back1],
      }
    }
    case "issue": {
      const id = mode.id, s = stuck?.blockers.shown.find((x) => x.issue_id === id)
      if (!stuck) return { title: `ISSUE #${id}`, rows: [{ segs: [waiting("looking…")] }], actions: [back1] }
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
      if (!rack) return { title: "THE RACK", rows: [{ segs: [waiting("probing…")] }], actions: [back1] }
      const ok = (b: boolean, s: string): Row => ({ segs: [{ s: b ? "● " : "✕ ", fg: b ? ROLE.live : ROLE.alarm }, plain(s)] })
      const up = rack.up_s < 3600 ? `${Math.floor(rack.up_s / 60)}m` : rack.up_s < 86400 ? `${Math.floor(rack.up_s / 3600)}h` : `${Math.floor(rack.up_s / 86400)}d`
      const rows: Row[] = [
        ...rack.problems.map((p) => ({ segs: [pink("! "), plain(p)] })),
        ok(true, `tlon ${rack.version}, up ${up}`), ok(rack.db, "the database answers"), ok(rack.jobs, rack.jobs ? "the job queue runs (staffing, sweeps, schedules)" : "no job queue on this node"),
        ok(rack.failed_jobs === 0, `${rack.failed_jobs} failed job(s) today`), ok(rack.tmux, "tmux is there for the coworkers"),
        { segs: [dim(`disk ${rack.disk_pct ?? "?"}% · memory ${rack.mem_pct ?? "?"}% · load ${rack.load ?? "?"}`)] },
        { segs: [plain("")] },
        { segs: [key("CHECKS QUEUE"), dim("  one full check at a time")] },
        ...(rack.checks?.running ? [{ segs: [{ s: "▶ ", fg: ROLE.live }, plain(rack.checks.running)] }] : [{ segs: [dim("  idle")] }]),
        ...(rack.checks?.waiting ?? []).map((w, i): Row => ({ segs: [dim(`${i + 1}. `), plain(w)] })),
        { segs: [plain("")] },
        { segs: [key("MERGE QUEUE"), dim("  approved worklines, landing one at a time")] },
        ...((rack.merge_queue ?? []).length
          ? (rack.merge_queue ?? []).map((m): Row => ({ segs: [{ s: m.state === "landing" ? "▶ " : "⧗ ", fg: m.state === "landing" ? ROLE.live : ROLE.inactive }, tidSeg(m.thread_id), plain(m.title)], open: () => goThread(m.thread_id, null) }))
          : [{ segs: [dim("  empty")] }]),
      ]
      return { title: `THE RACK · ${rack.state === "ok" ? "all green" : "needs a look"}`, rows, actions: [back1] }
    }
    case "memory": {
      if (!shelf) return { title: "MEMORY", rows: [{ segs: [waiting("taking the books down…")] }], actions: [back1] }
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
          ...(at?.habit ? [{ ...bind("memory.a"), run: () => void did(data.habit(at.habit!.id, "approve")).then(reload) }, { ...bind("memory.r"), run: () => void did(data.habit(at.habit!.id, "reject")).then(reload) }] : []),
          ...(at?.fact ? [{ ...bind("memory.d"), run: () => ask2(`forget "${at.fact!.text.slice(0, 50)}"`, () => void did(data.forget(at.fact!.id)).then(reload)) }] : []),
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
          { ...bind("build.up"), run: mutate((x) => move(x, 0, -1)) },
          { ...bind("build.down"), run: mutate((x) => move(x, 0, 1)) },
          { ...bind("build.left"), run: mutate((x) => move(x, -1, 0)) },
          { ...bind("build.right"), run: mutate((x) => move(x, 1, 0)) },
          { ...bind("build.enter", b.carrying ? "drop" : "pick up"), run: mutate((x) => (x.carrying ? drop(x) : pickUp(x))) },
          { ...bind("build.n"), run: mutate((x) => place(x)) },
          { ...bind("build.x"), run: mutate((x) => remove(x)) },
          { ...bind("build.r"), run: mutate((x) => rotate(x)) },
          { ...bind("build.u"), run: mutate((x) => undo(x)) },
          { ...bind("build.esc"), run: () => { back(true); roomChanged = true; draw() } },
        ],
      }
    }
    case "boss": {
      const rows: Row[] = [{ segs: [plain(all.awaiting ? `${all.awaiting} thread(s) wait on you across the office` : "nothing waits on you")] }]
      for (const x of all.workspaces) {
        const n = all.threads.filter((t) => t.workspace_id === x.id && needsYou(t)).length, s = all.triage[String(x.id)] ?? 0
        rows.push({ segs: [key(x.id === ws ? "◆ " : "  "), plain(x.name.padEnd(16)), n ? pink(`${n} waiting  `) : dim(""), s ? dim(`${s} issues`) : dim("")], open: () => goWs(x.id) })
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
          back1,
        ],
      }
    }
    case "card": {
      if (!card || w === null) return { title: "SETTINGS", rows: [{ segs: [waiting("reading…")] }], actions: [back1] }
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
      const tid = mode.tid, notes = reviewNotes.get(tid) ?? []
      if (!review) return { title: `REVIEW · #${tid}`, rows: [{ segs: [waiting("reading the branch…")] }], actions: [back1] }
      type At = { path: string; line?: number; side?: "+" | "-" | " "; hunk?: boolean }
      const same = (n: data.ReviewNote, at: At) => n.path === at.path && n.line === at.line && n.side === at.side
      const rows: Row[] = []
      const noteRows = (at: At) => { for (const n of notes) if (same(n, at)) rows.push({ segs: [dim("        "), { s: `✎ ${n.text}`, fg: ROLE.attention }], ref: at }) }
      const noteOn = (at: At) => ask(at.line ? `note on ${at.path}:${at.line}` : `note on ${at.path}`, (s) => {
        if (!s.trim()) return
        reviewNotes.set(tid, [...(reviewNotes.get(tid) ?? []).filter((n) => !same(n, at)), { path: at.path, line: at.line, side: at.side, text: s.trim() }]); draw()
      }, { text: notes.find((n) => same(n, at))?.text ?? "" })
      for (const f of review.files) {
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
      if (!review.files.length) rows.push({ segs: [dim("the branch changes nothing yet")] })
      const here = rows[sel]?.ref as At | undefined
      const jump = (dir: 1 | -1, want: (a: At, i: number) => boolean) => {
        for (let i = sel + dir; i >= 0 && i < rows.length; i += dir) if (rows[i]?.ref && want(rows[i]!.ref as At, i)) { sel = i; return draw() }
      }
      const isFile = (a: At) => !a.line && !a.hunk
      const submit = () => ask(`review #${tid}: a summary (optional) · tab: the verdict`, (s, [verdict]) => {
        const sent = data.reviewSubmit(tid, verdict as string, s, reviewNotes.get(tid) ?? [])
        // the notes are kept until the server takes them: a refused submit loses nothing
        void did(sent.then((msg) => { if (!msg.includes(" failed: ")) { reviewNotes.delete(tid); back() } return msg }))
      }, { cycles: [{ name: "verdict", values: [{ label: "comment", value: "comment" }, { label: "request changes", value: "changes" }, { label: "approve", value: "approve" }], i: 0 }] })
      return {
        title: `REVIEW · #${tid}${review.head ? ` @ ${review.head.slice(0, 7)}` : ""} · ${review.files.length} files · ${notes.length} notes · ⏎ notes the selected line`,
        rows,
        actions: [
          { ...bind("review.a"), run: () => { if (here && !here.hunk) noteOn(here) } },
          { ...bind("review.A"), run: () => { if (here) noteOn({ path: here.path }) } },
          ...(here && notes.some((n) => same(n, here)) ? [{ ...bind("review.x"), run: () => { reviewNotes.set(tid, notes.filter((n) => !same(n, here))); draw() } }] : []),
          { ...bind("review.n"), run: () => jump(1, (a) => !!a.hunk) }, { ...bind("review.p"), run: () => jump(-1, (a) => !!a.hunk) },
          { ...bind("review.N"), run: () => jump(1, isFile) }, { ...bind("review.P"), run: () => jump(-1, isFile) },
          { ...bind("review.s", `submit${notes.length ? ` ${notes.length} notes` : ""}…`), run: submit },
          back1,
        ],
      }
    }
    case "whimsy": {
      const rows: Row[] = whimsyRows(whim).map((w) => ({
        segs: [plain(w.label.padEnd(16)), { s: w.value.padEnd(10), fg: ROLE.key }, dim(w.note ?? "")],
        open: () => { setWhim(w.next(whim)); draw() },
      }))
      return {
        title: `${whimsyTitle(whim)} · ⏎ changes the selected dial`, rows,
        actions: [{ ...bind("whimsy.0"), run: () => { setWhim(resetToPreset(whim)); draw() } }, back1],
      }
    }
    case "settings": {
      if (!settings) return { title: "THE RUNNING SYSTEM", rows: [{ segs: [waiting("reading…")] }], actions: [back1] }
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
          { ...bind("settings.Z"), run: () => open({ kind: "whimsy" }) },
          ...(settings.restart_pending ? [{ ...bind("settings.x"), run: () => void did(data.restartCancel()).then(reload) }] : []),
          back1,
        ],
      }
    }
    case "needs": {
      // what waits on you: blocking first (work has stopped), then what to decide; then what's under way
      const row = (n: data.Need): Row => ({
        segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(n.thread_id ? [tidSeg(n.thread_id)] : []),
          { s: n.title, fg: ROLE.prose }, dim(`  ${ago(n.at)}  `), { s: n.text.replace(/\s+/g, " "), fg: n.level === "blocking" ? ROLE.prose : ROLE.inactive }],
        open: n.thread_id ? () => openReader(n.thread_id!) : undefined, ref: n,
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
      const acts: Action[] = !n ? [] : [...needActions(n), { ...bind("needs.f"), run: () => open({ kind: "decide", i: Math.max(0, needs.indexOf(n)) }) }]
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
      actions: [{ ...bind("babel.n"), run: openBabel }, back1],
    }
    case "entry": {
      const e = entryOf(a, boardCtx(), needs, feed, new Date())
      const row = (text: string, x: Act | null): Row => ({ segs: [plain(text)], open: x ? () => act(x) : undefined })
      // Uqbar lives on its study: where it is now, and the verbs that reach it there
      const study = studyOf(all.threads, ws), me = all.roster.find((r) => r.agent === "uqbar")
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
      const order = [...needs.filter((x) => x.level === "blocking"), ...needs.filter((x) => x.level === "decide")]
      if (!order.length) return { title: "WAITING ON YOU", tint: ROLE.live, rows: [{ segs: [{ s: "nothing waits on you. ", fg: ROLE.live }, dim("the crew is getting on with it.")] }], actions: [back1] }
      const i = Math.min(mode.i, order.length - 1), n = order[i]!, tid = n.thread_id ?? null
      const t = tid ? all.threads.find((x) => x.id === tid) : undefined
      const step = (d: number) => open({ kind: "decide", i: (i + d + order.length) % order.length })
      const rows: Row[] = [
        { segs: [{ s: ` ${NEED_KIND[n.kind]} `, fg: ROLE.ground, bg: NEED_TONE[n.kind] }, plain(" "), ...(tid ? [tidSeg(tid)] : []), { s: n.title, fg: ROLE.prose, bold: true }], open: tid ? () => openReader(tid) : undefined },
        { segs: [dim(`${n.level === "blocking" ? "work has stopped until you act" : "nothing waits on this"} · ${ago(n.at)}${t ? ` · ${t.lead ?? "no lead"}${t.stage ? ` at ${t.stage}` : ""}` : ""}`)] },
        { segs: [plain("")] },
        ...wrap(n.text, paneW() - 4).map((l): Row => ({ segs: [plain(l)] })),
      ]
      return {
        title: `DECIDE · ${i + 1} of ${order.length}`,
        tint: n.level === "blocking" ? ROLE.attention : ROLE.body,
        rows,
        actions: [...needActions(n), { ...bind("decide.n"), run: () => step(1) }, { ...bind("decide.p"), run: () => step(-1) }, { ...bind("decide.l"), run: () => open({ kind: "needs" }) }, back1],
      }
    }
    case "ideas": {
      const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
      const rows: Row[] = ideas.map((n) => ({ segs: [who(n.author), plain(n.body)], ref: n }))
      const picked = rows[sel]?.ref as CorkNote | undefined, w = ws
      const gone = (id: number) => { ideas = ideas.filter((x) => x.id !== id); room().suggestionBox(ideas) }
      return {
        title: `SUGGESTION BOX · ${ideas.length} · the crew's ideas, yours to file or throw out`, rows: rows.length ? rows : [{ segs: [dim("the box is empty. a coworker drops an idea in it when they see one while working.")] }],
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
      const rows: Row[] = [...said].reverse().flatMap((x) => wrap(x.line, paneW() - 14 - x.who.length).map((l, n): Row => ({ segs: n ? [dim(" ".repeat(9 + x.who.length)), plain(l)] : [at(x.at), who(x.who), plain(l)] })))
      return {
        title: `BANTER · the last ${said.length} lines said in the room, newest first`,
        rows: rows.length ? rows : [{ segs: [dim("nobody has said anything yet. the crew talks when two of them meet.")] }],
        actions: [back1],
      }
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
            { ...bind("pet.S.cat"), run: () => { savePets({ cat: { species: draft.species, temperament: named ?? { ...draft.temperament } } }); petsSeen = ""; followPets(); back(); roomChanged = true; draw() } },
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
        title: "ARGOS", rows: [{ segs: [plain(wideRoom ? "the office dog. good boy." : "Argos lives in the wide room — make the terminal wider to see him.")] }],
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
      const m = mode, name = m.name
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
          // ⏎ is the lit row (it cycles a field); save has its own key
          { ...bind("look.s"), run: () => { saveLook(name, draft); lookDraft = null; back(); roomChanged = true; draw() } },
          { ...bind("look.r"), run: () => { Object.assign(draft, rollLook(`${name}:${rolls++}`)); draw() } },
          { ...bind("look.e"), run: () => {
            editBuf = { front: draft.custom?.front ? [...draft.custom.front] : blankBuf(), side: draft.custom?.side ? [...draft.custom.side] : blankBuf(), back: draft.custom?.back ? [...draft.custom.back] : blankBuf() }
            editEntry = { front: [...editBuf.front], side: [...editBuf.side], back: [...editBuf.back] }
            editCursor = { x: 0, y: 0 }; editScroll = 0
            mode = { kind: "look-editor", name, view: "front", from: m.from }; sel = 0; snapSel = true; draw()
          } },
          back1,
        ],
      }
    }
    case "hall": {
      const c = candidateOf(hall, hallCtx())
      const rows: Row[] = hallRows(c, hall.locks).map((r) => ({
        segs: r.segs,
        open: r.lock ? () => { hallSet({ ...hall, locks: toggleLock(hall.locks, r.lock!.kind, r.lock!.key) }); draw() } : undefined,
      }))
      return {
        title: `HIRING HALL · ${hall.seed} · ${hall.pile.length} maybe`, rows,
        actions: [
          { ...bind("hall.left"), run: () => { hallSet(pass(hall, hallCtx())); draw() } },
          { ...bind("hall.up"), run: () => { hallSet(maybe(hall, hallCtx())); draw() } },
          { ...bind("hall.right"), run: () => void hallHire() },
          { ...bind("hall.space"), run: () => rows[sel]?.open?.() },
          { ...bind("hall.m"), run: () => open({ kind: "hall-pile" }) },
          back1,
        ],
      }
    }
    case "store": {
      const taken = storeTaken(), c = storeCandidate(store, taken), slot = slotOf(c.species) ?? "cat"
      const occupant = (petsNow ?? resolvePets(loadPets()))[slot]
      const rows: Row[] = storeRows(c, store.locks, occupant.name, previewOf({ name: c.name, species: c.species, temperament: c.temperament }, previewTick).line).map((r) => ({
        segs: r.segs,
        open: r.lock ? () => { storeSet(storeToggle(store, r.lock!)); draw() } : undefined,
      }))
      return {
        title: `PET STORE · ${store.seed}`, rows,
        actions: [
          { ...bind("store.left"), run: () => { storeSet(shelve(store, -1, storeTaken())); draw() } },
          { ...bind("store.right"), run: () => { storeSet(shelve(store, 1, storeTaken())); draw() } },
          { ...bind("store.up"), run: () => { storeSet(storePass(store, storeTaken())); draw() } },
          { ...bind("store.down"), run: () => { storeSet(storeBack(store, storeTaken())); draw() } },
          { ...bind("store.space"), run: () => rows[sel]?.open?.() },
          { ...bind("store.e"), run: () => ask("name", (s) => { if (s.trim()) { storeSet(rename(store, s.trim())); draw() } }, { text: c.name }) },
          { ...bind("store.enter"), run: storeAdopt },
          back1,
        ],
      }
    }
    case "hall-pile": {
      const rows: Row[] = hall.pile.map((e, i) => {
        const c = candidateOf({ ...hall, seed: e.seed, overrides: e.overrides, locks: {} }, hallCtx())
        return { segs: [plain(c.name.padEnd(14)), dim(`${c.grade} ${c.archetype} · ${c.specialty} · ${e.seed}`)], ref: i, open: () => { hallSet(bringBack(hall, i)); open({ kind: "hall" }) } }
      })
      return {
        title: `MAYBE PILE · ${hall.pile.length}`,
        rows: rows.length ? rows : [{ segs: [dim("nobody yet — ↑ in the hall keeps a candidate here")] }],
        actions: [
          { ...bind("hall-pile.x"), run: () => { const i = rows[sel]?.ref; if (typeof i === "number") { hallSet({ ...hall, pile: dropPile(hall.pile, i) }); sel = Math.max(0, sel - 1); draw() } } },
          { ...bind("hall-pile.esc"), run: () => open({ kind: "hall" }) },
        ],
      }
    }
    case "help": {
      const m = mode
      const sect = (name: string, hs: Hint[]): Row[] => hs.length ? [{ segs: [key(name)] }, ...hs.map((h) => ({ segs: [plain("  "), { s: h.key.padEnd(10), fg: ROLE.key, bold: true }, plain(h.label)] }))] : []
      return {
        title: `HELP · ${m.title}`,
        rows: [...sect(m.title.toLowerCase(), m.keys), ...sect("everywhere", GLOBALS), ...sect("reading a thread (its card's keys work there too)", READER_KEYS), ...(world ? sect("the sandbox's play keys (they win over a card's)", PLAY) : []), ...boardLegend()],
        actions: [{ ...bind("help.esc", `back to ${m.title.toLowerCase()}`), run: () => { mode = m.from; sel = 0; scroll = 0; snapSel = true; draw() } }],
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
      const hint = (id: KeyId, label: string) => { const k = bind(id, label).key.split(" "); return k.length > 3 ? label : `${k.map(keyName).join("/")} ${label}` }
      rows.push({ segs: [dim([hint("lookedit.view", `view (${view})`), hint("lookedit.mirror", `mirror (${editMirror ? "on" : "off"})`), hint("lookedit.paint", "letter paints"), hint("lookedit.clear", "clears"), hint("lookedit.save", "save"), hint("lookedit.discard", "discard")].join(" · "))] })
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
  } else if (process.env.OFFICE_WIDE) {
    // half blocks have no cell size to ask for, so a drive opts in: the wide room at whatever scale fits the window
    next = Math.max(WIDE_MIN_W, Math.floor(colsN / Math.max(0.25, ((rowsN - DETAIL - 3) * 2) / WIDE_H)))
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
    out(reader.draw(colsN, termRows, threadOf(reader.tid), [...threadActions(reader.tid, true).map((x) => `${x.key} ${x.label}`), "pgup/pgdn scroll", "esc back", "ctrl+] room"].join(" · ")))
    return
  }
  const a = view()
  let o = `${ESC}[?2026h${ESC}[?25l`
  // header: the workspace, and what waits elsewhere
  const blocking = needs.filter((n) => n.level === "blocking").length, deciding = needs.length - blocking, usage = usageHeader(all, Date.now())
  const head: (Seg & { go?: () => void })[] = [{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(), fg: ROLE.body, bold: true }, key(" › "),
    ...(all.ok ? [] : [{ s: `  ${downHeader(all, Date.now())}`, fg: ROLE.alarm }]),
    ...(blocking ? badge({ s: `  ⚑ ${blocking} blocking `, fg: ROLE.ground, bg: ROLE.attention, bold: true, go: inbox }) : []),
    ...(deciding ? [{ s: `  ${blocking ? "· " : "⚑ "}${deciding} to decide`, fg: ROLE.body, go: inbox }] : []),
    ...(needs.length ? [{ ...dim("  (i)"), go: inbox }] : []),
    ...(shiftHeader() ? [{ s: `  ${shiftHeader()}`, fg: ROLE.body, go: toggleShift }] : []),
    ...(all.pause === "pencils_down" || all.pause === "lights_out" ? badge({ s: all.pause === "lights_out" ? "  ◼ lights out " : "  ✎ pencils down ", fg: ROLE.ground, bg: ROLE.attention, bold: true, go: () => ask2("back to work", () => void did(data.pause("back_to_work"))) }) : []),
    ...(queuesHeader() ? [{ s: `  ${queuesHeader()}`, fg: ROLE.live, go: () => open({ kind: "health" }) }] : []),
    ...(lifeHeader(all, ws) ? [{ s: `  ${lifeHeader(all, ws)}`, fg: ROLE.body }, dim("  (L)")] : []),
    ...(usage ? [{ s: `  ${usage.text}`, fg: usage.hot ? ROLE.attention : ROLE.body, bold: usage.hot }] : []),
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
    // the annex below the office grows or shrinks with the home, and the room's rows with it
    layoutScreen()
  }
  homeShown = building
  const vp = building ? { x: 0, y: 0, w: viewport.w, h: viewport.h } : viewport
  if (building) {
    frame = renderHome({ home: build!.home, cursor: build!.cursor, carrying: build!.carrying, refused: build!.refused, w: Math.ceil(vp.w), h: Math.ceil(vp.h), weather: a.weather?.kind, mail: mailbox(needs) })
    imageDirty = true
  } else if (fresh || roomChanged) { frame = room0.render(a, { picked: lit ?? picked, armed: null, person: mode.kind === "person" ? mode.name : null, tray: unread(), board: boardCtx() }, measureFor(g), world?.now()); roomChanged = false }
  const seen = clipFrame(frame!, vp)
  if (!building) addMargin(seen, vp)
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
  acts = []
  if (picker) {
    const shown = rank(picker.q.text, picker.items, (p) => p.text)
    picker.sel = Math.min(picker.sel, Math.max(0, shown.length - 1))
    title = `${picker.title}: ${picker.q.text}`
    segRows = shown.map((p) => ({ segs: p.segs, open: p.run }))
    keys = "type to narrow · ↑↓ move · enter pick · esc close · ctrl+] room"
    cursor = { r: -1, c: title.length + 1 }
    sel = picker.sel
  } else if (input?.ed.multiline) {
    const v = input.ed.view(colsN - 6, Math.max(1, termRows - top - 3))
    title = input.label
    segRows = [{ segs: cyclesSegs(input) }, ...v.rows.map((r) => ({ segs: [pink(" ▌ "), plain(r)] }))]
    keys = `enter done · alt-enter newline${input.cycles?.length ? ` · tab change the lit choice${input.cycles.length > 1 ? " · shift-tab the next choice" : ""}` : ""} · esc cancel · ctrl+] room`
    cursor = { r: v.cursor.r + 1, c: v.cursor.c + 3 }
  } else {
    const d = detail()
    const add = adder(`card:${mode.kind}`)
    title = d.title; acts = d.actions; tint = d.tint ?? ROLE.key
    segRows = d.rows.length ? d.rows : [{ segs: [dim(`nothing here yet${add ? ` — ${keyName(add.key)} ${add.label}` : ""}`)] }]
  }
  rows = segRows
  const split = acts.length > 0 && colsN >= 80
  const leftW = split ? colsN - ACTIONS_W - 1 : colsN
  const box = picker || input ? null : cardBox(), bv = box?.ed.view(leftW - 4, 4), boxH = bv ? bv.rows.length + 1 : 0
  if (box?.focused) keys = "enter send · alt-enter newline · esc leave the box · pgup/pgdn scroll · ctrl+] room"
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
    room = Math.max(1, termRows - footN - 1 - top - boxH)
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
  const boxAt = top + 1 + room
  if (box && bv) {
    const on = box.focused
    o += `${ESC}[${boxAt};1H` + line([{ s: " reply ", fg: ROLE.ground, bg: on ? ROLE.attention : ROLE.inactive }, dim(on ? "" : `  r${acts.some((x) => x.key === "enter") ? "" : " or ⏎"} to write`)], leftW)
    bv.rows.forEach((r, i) => { o += `${ESC}[${boxAt + 1 + i};1H` + line([on ? pink(" ▌ ") : dim(" ▌ "), on ? plain(r) : dim(r)], leftW) })
    if (split) for (let i = 0; i < boxH; i++) o += `${ESC}[${boxAt + i};${leftW + 1}H` + line([dim("│")], 1) + line([], ACTIONS_W)
  }
  // the foot: what you are typing, a confirm, or the keys — the lit one when the actions have them and no column shows it
  o += `${ESC}[${termRows - footN};1H` + line([], colsN)
  const one = input && !input.ed.multiline ? input : null
  const litKey = !split && !selectable && acts[asel] ? keyName(acts[asel]!.key) : null
  const hintSegs = (l: Hint[]): Seg[] => l.flatMap((h, j): Seg[] => [...(j ? [dim(" · ")] : []), h.key === litKey ? { s: `${h.key} ${h.label}`, fg: ROLE.ground, bg: ROLE.key } : { s: h.key, fg: ROLE.key, bold: true }, ...(h.key === litKey ? [] : [plain(` ${h.label}`)])])
  const feet: Seg[][] = one ? [[pink(` ${one.label}: `), plain(one.ed.text), ...(one.cycles?.length ? [dim("   tab: "), ...cyclesSegs(one)] : [])]] : confirm ? [[pink(` ${confirm.label} (y/n) · enter is y`)]] : keys ? [[dim(` ${keys}`)]] : foot.map((l) => [plain(" "), ...hintSegs(l)])
  for (let i = 0; i < footN; i++) o += `${ESC}[${termRows - footN + 1 + i};1H` + line(feet[i] ?? [], colsN)
  o += `${ESC}[?7h`
  if (one) {
    const pre = [...` ${one.label}: `].length
    o += `${ESC}[${termRows};${pre + one.ed.col + 1}H${ESC}[?25h`
  } else if (box?.focused && bv && !confirm) o += `${ESC}[${boxAt + 1 + bv.cursor.r};${4 + bv.cursor.c}H${ESC}[?25h`
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
    mode = { kind: "look-editor", name, view: k === "1" ? "front" : k === "2" ? "side" : "back", from: mode.from }
    return draw()
  }
  if (k === "esc") {
    if (editEntry) editBuf[view] = [...editEntry[view]]
    mode = { kind: "look", name, from: mode.from }; sel = 0; snapSel = true; return draw()
  }
  if (k === "enter") {
    if (lookDraft) {
      const custom = trimCustom(editBuf)
      if (custom) lookDraft.custom = custom
      else delete lookDraft.custom
    }
    mode = { kind: "look", name, from: mode.from }; sel = 0; snapSel = true; return draw()
  }
  if (k === ".") return paintAt(".")
  if ((LEGEND_CHARS as readonly string[]).includes(k)) return paintAt(k)
}

/** the help card over the card you are on: its keys, the globals, the reader's and, in the sandbox, the play keys */
function help() {
  if (mode.kind === "help") return
  const d = detail()
  open({ kind: "help", from: mode, title: d.title, keys: d.actions.map((x) => ({ key: keyName(x.key), label: x.label })) })
}

// the last keys pressed, for the Konami code
let keyLog: string[] = []

/** sandbox only: one key, one thing to do with the toy; true when the key was one of them */
function toyKey(k: string): boolean {
  if (!world) return false
  const r = room(), under = mode.kind === "person" ? mode.name : null
  switch (k) {
    case "D": r.play("doorbell"); status = "ding dong"; break
    case "E": r.play("event"); status = r.eventNow() ? `event: ${r.eventNow()!.kind}` : r.eventsHere() ? (Object.values(resolveWhim(whim).events).some(Boolean) ? "something's up" : "events are switched off (the wackiness dial)") : "events need the wide room (kitty graphics)"; break
    case "F": status = r.play("drill") ? "fire drill!" : "a scene is running — no drill until it ends"; break
    case "T": r.catDo("come"); if (r instanceof WideRoom) r.dogDo("office"); status = "treat! they come running"; break
    case "N": world.toggleNight(); for (const x of rooms.values()) x.setClock(world.now); status = world.now().getHours() === 23 ? "night falls" : "morning"; break
    case "W": world.nextWeather(); status = `weather: ${world.snapshot().weather!.desc.toLowerCase()}`; void refresh(); break
    case "P": if (mode.kind === "pet" && mode.who === "dog" && r instanceof WideRoom) r.patDog(); else if (under) r.pat(under); else r.pet(); status = "pat pat"; break
    case "C": world.callOver(under ?? world.snapshot().bench[1]!.name); status = `calling someone over to ${under ?? "the desk"}`; void refresh(); break
    default: return false
  }
  changed(); draw(); return true
}

function onKey(k: string) {
  keyLog = [...keyLog, k].slice(-KONAMI.length)
  if (isKonami(keyLog)) { keyLog = []; room().disco(); status = "↑↑↓↓←→←→BA — everybody dance"; changed(); return draw() }
  if (k === ROOM_CTRL) return toRoom()
  if (picker) return pickerKey(k)
  if (input) return inputKey(k)
  if (confirm) {
    const c = confirm; confirm = null
    if (k === "y" || k === "enter") c.run()
    else { status = "cancelled"; if (reader) reader.status = status }
    return draw()
  }
  if (mode.kind === "look-editor") return editorKey(k)
  if (mode.kind === "hall" && (k === "tab" || k === "backtab")) { snapSel = false; sel = stepRow(sel, k === "tab" ? 1 : -1); return draw() }
  if (mode.kind === "store" && (k === "tab" || k === "backtab")) { snapSel = false; sel = stepStoreRow(sel, k === "tab" ? 1 : -1); return draw() }
  if (reader) {
    const r = reader.key(k, Math.max(1, (process.stdout.rows ?? 24) - 6))
    if (r === "leave") return closeReader()
    if (r === "pass") return threadActions(reader.tid, true).find((x) => x.key === k)?.run()
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
    case "enter":
      if (mode.kind === "home" && lit !== null && !reader) return act({ kind: "thread", tid: lit })
      return onActions ? acts[asel]?.run() : rows[sel]?.open?.()
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
    case "L": if (all.life?.[String(ws)]) open({ kind: "life" }); return
    case "B": if (flagOn(all, "build_mode")) open({ kind: "build" }); return
    case "U": return open({ kind: "entry" })
    case "O": return open({ kind: "boss" })
    case "S": return open({ kind: "settings" })
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
  const box = cardBox()
  if (box) { box.ed.insert(text); box.focused = true; return draw() }
}

/** the margin notes over a clipped frame: text ink after the clip so a pan can't push it off-screen, hits first so they win */
function addMargin(fr: Frame, vp: Viewport) {
  looks.see(notes, focused)
  const m = marginInk(notes, looks, lit, vp, g ? measureFor(g) : undefined)
  fr.ink.push(...m.ink)
  fr.hits.unshift(...m.hits)
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
  const clipped = clipFrame(frame, viewport)
  addMargin(clipped, viewport)
  const h = hitAt(clipped, g, m.col, m.row, viewport)
  if (m.motion) {
    const t = h?.tip ?? "", over = h?.note ?? null
    if (over !== lit) { lit = over; tip = t; roomChanged = true; return draw() }
    if (t !== tip) { tip = t; draw() }
    return
  }
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
// which goes to the room.
let zoom: { view: TerminalView; label: string; after?: () => void } | null = null
const ROOM_KEY = 0x1d // Ctrl-]
/** Ctrl-] as `tokenize` names it: a control character is ctrl- and its byte + 0x60 */
const ROOM_CTRL = "ctrl-}"

async function zoomInto(tid: number) {
  const target = await data.terminal(tid)
  if (!target) { status = `#${tid} has no live terminal`; if (reader) reader.status = status; return draw() }
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
  if (ws === null) return
  const p = await data.dumpPage(ws, id)
  if (!p) { status = "that page can't be read: the server isn't answering"; return draw() }
  pageThrough(`page-${ws}-${id}`, p.body, `the dump · ${stamp(p.at)}`)
}
/** an earlier page made the dump again; the page it replaces is kept, so this is undone the same way */
async function restorePage(id: number) {
  if (ws === null) return
  const w = ws, p = await data.dumpPage(w, id)
  if (!p) { status = "that page can't be read: the server isn't answering"; return draw() }
  if (Bun.spawnSync(["tmux", "-L", OWN_TMUX, "has-session", "-t", `=dump-${w}`]).exitCode === 0) { status = "the dump is open in its editor: close it first, then put the page back"; return draw() }
  let file: string | null = null
  try { file = readFileSync(dumpFile(w), "utf8") } catch {}
  const now = await data.dump(w)
  if (!now) { status = "the dump can't be read: the server isn't answering"; return draw() }
  if (dumpSending.has(w) || (file?.trim() && file !== now.body)) { status = "the dump has a save still on its way: D to send it, then put the page back"; return draw() }
  await did(data.dumpPut(w, p.body).then((r) => {
    if (r.ok) { dumpSent.set(w, p.body); mkdirSync(dirname(dumpFile(w)), { recursive: true }); writeFileSync(dumpFile(w), p.body) }
    return r.line
  }))
  await loadCard(); draw()
}
/** the home's dump in the operator's own editor, in the office's tmux. Every save goes to the server, one PUT at
 *  a time per home (a write that lands mid-PUT is sent when it settles), and one the server didn't take is sent on
 *  the next write, leave, open or refresh: a file that differs from the server's page is never overwritten, it is sent —
 *  safe because the server keeps the page each save replaces. A session already open is reattached, never rewritten */
const dumpSent = new Map<number, string>(), dumpSending = new Set<number>(), dumpAgain = new Set<number>(), dumpWatched = new Set<number>(), dumpFailedAt = new Map<number, number>(), dumpOldWatched = new Set<number>()
// on disk, not the runtime tmpfs: words the server hasn't taken yet survive a logout or a reboot
const dumpFile = (w: number) => join(STATE_DIR, OWN_TMUX, `dump-${w}.md`)
function syncDump(w: number, quiet = false) {
  let text: string
  try { text = readFileSync(dumpFile(w), "utf8") } catch { return }
  if (text === dumpSent.get(w)) return
  if (dumpSending.has(w)) { dumpAgain.add(w); return }
  if (!text.trim()) { if (quiet) return; status = "the dump came back blank — not saved; the last page stands"; return draw() }
  // a quiet retry waits a minute after a refusal, so a server away or refusing is not hammered
  if (quiet && Date.now() - (dumpFailedAt.get(w) ?? 0) < 60_000) return
  dumpSending.add(w)
  const put = data.dumpPut(w, text).then((r) => {
    dumpSending.delete(w)
    if (r.ok) { dumpSent.set(w, text); dumpFailedAt.delete(w) } else dumpFailedAt.set(w, Date.now())
    if (dumpAgain.delete(w)) syncDump(w)
    return r
  })
  // quiet runs from inside a refresh, so it must not start another (`did` does)
  if (quiet) void put.then((r) => { if (r.ok) { status = r.line; draw() } })
  else void did(put.then((r) => r.line)).then(loadCard).then(draw)
}
async function openDump() {
  if (ws === null) return
  const w = ws, session = `dump-${w}`, file = dumpFile(w), tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  const open = tmux("has-session", "-t", `=${session}`).exitCode === 0
  // an editor an older office started writes to the runtime dir: its words are brought across, and kept coming while it is open
  const old = `${OWN_DIR}/dump-${w}.md`
  if (existsSync(old)) {
    mkdirSync(dirname(file), { recursive: true })
    const bring = () => { try { const t = readFileSync(old, "utf8"); if (t.trim()) writeFileSync(file, t) } catch {} }
    bring()
    if (open && !dumpOldWatched.has(w)) { dumpOldWatched.add(w); watchFile(old, { interval: 1000 }, bring) }
    else unlinkSync(old)
  }
  if (!open || !dumpSent.has(w)) {
    const page = await data.dump(w)
    if (!page) { status = "the dump can't be read: the server isn't answering"; return draw() }
    if (!dumpSending.has(w)) dumpSent.set(w, page.body)
  }
  if (!dumpWatched.has(w)) { dumpWatched.add(w); watchFile(file, { interval: 1000 }, () => syncDump(w)) }
  if (!open) {
    let unsent: string | null = null
    try { unsent = readFileSync(file, "utf8") } catch {}
    if (unsent?.trim() && unsent !== dumpSent.get(w)) { status = "sending what you wrote while the server was away"; syncDump(w) }
    else { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, dumpSent.get(w)!) }
    // VISUAL/EDITOR is a shell command, as git reads it: flags work, and a path with spaces is quoted inside it
    const edit = `e="\${VISUAL:-\${EDITOR:-}}"; [ -n "$e" ] || e="$(command -v nvim || command -v vi)"; [ -n "$e" ] || { echo "no editor: set VISUAL or EDITOR"; read _; exit 1; }; eval "exec $e \\"\\$0\\""`
    // a tmux server already up keeps its own env, so the editor this TUI was started with is handed over
    const env = ["VISUAL", "EDITOR"].flatMap((k) => (process.env[k] ? ["-e", `${k}=${process.env[k]}`] : []))
    tmux("new-session", "-d", "-s", session, "-n", "dump", ...env, "sh", "-c", edit, file)
  }
  zoomOn({ socket: OWN_TMUX, session, window: "dump" }, "the dump", () => syncDump(w))
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
function zoomOn(target: Target, label: string, after?: () => void) {
  const colsN = cols(), rowsN = Math.max(2, (process.stdout.rows ?? 24) - 1)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[?1003l${ESC}[?1006l${ESC}[?2004l${ESC}[2J`)
  zoom = { label, after, view: new TerminalView(target, colsN, rowsN, () => drawZoom(), () => leaveZoom()) }
  drawZoom()
}
function drawZoom() {
  if (!zoom) return
  const colsN = cols(), vt = zoom.view.vt
  // no autowrap while drawing: a row the VT and this terminal measure differently can't wrap and scroll the bar away
  let o = `${ESC}[?2026h${ESC}[?7l${ESC}[?25l${ESC}[1;1H` + line([{ s: " ROOM ", fg: ROLE.ground, bg: ROLE.attention }, key(" ctrl+] room "), { s: zoom.label, fg: ROLE.body, bold: true }], colsN)
  vtRows(vt).forEach((r, i) => { o += `${ESC}[${i + 2};1H${r}` })
  const b = vt.buffer.active
  o += `${ESC}[?7h${ESC}[${b.cursorY + 2};${b.cursorX + 1}H${ESC}[?25h${ESC}[?2026l`
  out(o)
}
function leaveZoom(toTheRoom = false): void {
  if (!zoom) return
  const z = zoom
  zoom = null
  z.view.close()
  out(`${ESC}[0m${ESC}[?25l${ESC}[?1003h${ESC}[?1006h${ESC}[?2004h`)
  z.after?.()
  if (toTheRoom) return toRoom()
  if (reader) { out(`${ESC}[2J`); return draw() }
  layoutScreen(); draw()
}
/** raw keys while zoomed: Ctrl-] goes to the room, the rest goes to the pane as it came */
function zoomInput(b: Uint8Array) {
  const at = b.indexOf(ROOM_KEY)
  if (at < 0) return zoom?.view.send(b)
  zoom?.view.send(b.subarray(0, at))
  leaveZoom(true)
}
/** Ctrl-] from anywhere: the room with nothing open over it */
function toRoom(): void {
  if (zoom) return leaveZoom(true)
  if (input && !input.ed.empty) banked.set(input.label, input.ed.text)
  bankReader()
  reader = null; input = null; back(true); roomChanged = true
  out(`${ESC}[?25l`); layoutScreen(); draw()
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
        else if (i.t === "focus") { focused = i.on; looks.focus(i.on); if (!i.on) stampLooked(); draw() }
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
  let sec = 0
  every(() => { looks.tick(1); if (focused && ++sec % 5 === 0) stampLooked(); if (!reader && !zoom && notes.some((n) => { const a = looks.alpha(n); return a < 1 && a > FLOOR })) draw() }, 1000)
  every(() => { if ((mode.kind === "pet" && petDraft) || mode.kind === "store") { previewTick += 10; draw() } }, 1000)
  every(() => { if (followPalette() || followLooks() || followSouls() || followPets() || followHall() || followStore()) { frame = null; draw() } }, 1000)
  // another surface (the desktop's alert) asks to show a thread: open it, once per request, ignoring
  // what was asked before this TUI started
  let seenFocus = (await data.focus())?.at ?? 0
  every(async () => {
    const f = await data.focus()
    if (!f || f.at <= seenFocus) return
    seenFocus = f.at
    if (zoom) leaveZoom()
    goThread(f.thread_id, threadOf(f.thread_id)?.workspace_id)
    openReader(f.thread_id, {}, false)
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
