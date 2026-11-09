import { parse as parseTally } from "../kit/trophies"
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { Looks, type Note } from "../kit/margin"
import { load as loadWhim } from "../kit/whimsy-file"
import { type State as WhimState } from "../kit/whimsy"
import { newLedger, type Ledger } from "../kit/scharlach"
import { boardColumns } from "../kit/crew"
import { type PetSetting, type Pets } from "../kit/pets"
import { type Build } from "../kit/home"
import { type LookOverride } from "../kit/looks"
import { hallSignature, loadHall, type Hall } from "../kit/hall"
import { castSignature, loadCast, type Cast } from "../kit/cast"
import { loadStore, type Store } from "../kit/store"
import { EMPTY, type Agents, type LifeStatus, type CorkNote, type ThreadView } from "../kit/types"
import { RailRoom } from "../rooms/rail"
import { WideRoom } from "../rooms/wide"
import * as data from "./data"
import { toy } from "./sandbox"
import { Editor } from "./editor"
import { loadFloor } from "./home"
import { inSandbox } from "./pets"
import { type Geometry } from "./paint"
import { Reader } from "./reader"
import { type Hint } from "./pane"
import { type Seg } from "./term"
import { TerminalView } from "./terminal"
import { type Viewport } from "./viewport"
import { earmarksIn } from "../kit/plane"
import { CREW_GROUPS, CREW_SORTS, type Sort } from "./order"

export const STATE_DIR = join(process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"), "tlon")
export const STATE = join(STATE_DIR, "office-workspace")
export const TRAY = join(STATE_DIR, "office-tray") // when you last read the in-tray
export const SAID = join(STATE_DIR, "office-banter") // the room's last lines said, for the banter log
export const EARS = join(STATE_DIR, "office-earmarks") // the posts Argos caught, so a restart keeps their dog-ears
export const LOOKED = join(STATE_DIR, "margin-looked") // the last focused moment, epoch seconds: older margin notes start already seen
// the machine's palette, when it hands one in: `{ "role": { "<role>": "#rrggbb", … } }` (or the bare
// map). A link here that the machine repoints on a theme switch is followed within a second.
export const PALETTE = process.env.TLON_PALETTE ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/palette.json")
// `--sandbox`: the TUI on a made-up world (tui/sandbox.ts) instead of the server
export const SANDBOX = inSandbox()
// OFFICE_TOY_KEYS=1: the room's play keys (ROOM_PLAY) run on the real office too, a card's own key still wins
export const TOY_KEYS = process.env.OFFICE_TOY_KEYS === "1"
// the toy keeps its looks, souls and hall in a dir of its own, so a pretend hire never reaches the machine's files
export const CONFIG = SANDBOX ? join(tmpdir(), "tlon-sandbox") : join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon")
// per-agent look overrides, same poll shape as PALETTE above
export const LOOKS = process.env.TLON_LOOKS ?? join(CONFIG, "looks.json")
// per-coworker SOUL.md files, one `<name>.md` each, polled like LOOKS
export const SOULS = process.env.TLON_SOULS ?? join(CONFIG, "souls")
// the hiring hall: current seed + locks + edits and the maybe pile, polled like LOOKS
export const HALL = process.env.TLON_HALL ?? join(CONFIG, "hall.json")
// the cast editor's grade and specialty per seat (kit/cast.ts), polled the same way
export const CAST = process.env.TLON_CAST ?? join(CONFIG, "cast.json")
// the pet store: species + seed + locks + edits, polled the same way
export const STORE = process.env.TLON_STORE ?? join(CONFIG, "store.json")
// `mise run office:sandbox` (OFFICE_PLAY_INTRO=1) shows the play card once, the first time the sandbox is launched
export const PLAY_SEEN = join(CONFIG, "play-seen")
// the wackiness dial (kit/whimsy.ts): preset + overrides, remembered in the config dir
export const OFFICE = process.env.TLON_OFFICE ?? join(CONFIG, "office.json")
export const readState = (p: string) => { try { return readFileSync(p, "utf8").trim() } catch { return "" } }
export const writeState = (p: string, s: string) => { try { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, s) } catch { /* a read-only home: it just won't remember */ } }
/** the office's trophies (kit/trophies.ts): tallies kept across restarts, a cup on the lounge shelf for each one won */
export const TROPHY_FILE = SANDBOX ? join(CONFIG, "office-trophies") : join(STATE_DIR, "office-trophies")

export type Mode =
  | { kind: "home" } | { kind: "crew" } | { kind: "notes" } | { kind: "boss" } | { kind: "archive" }
  | { kind: "person"; name: string; from?: Mode } | { kind: "thread"; tid: number; from?: Mode }
  | { kind: "column"; col: number } | { kind: "ticket"; id: number; from?: Mode } | { kind: "epic"; id: number; from?: Mode } | { kind: "calendar" } | { kind: "life" } | { kind: "pages" }
  | { kind: "tray" } | { kind: "triage" } | { kind: "issue"; id: number; from?: Mode } | { kind: "health" } | { kind: "memory" } | { kind: "card" }
  | { kind: "runs"; id: number } | { kind: "run"; id: number; run: number } | { kind: "pet"; who: "cat" | "dog" } | { kind: "play"; from?: Mode; page?: 1 | 2 } | { kind: "arcade" } | { kind: "ideas" } | { kind: "banter" } | { kind: "trophies" } | { kind: "needs" } | { kind: "decide"; i: number } | { kind: "babel"; page: string[] } | { kind: "entry" }
  | { kind: "build" } | { kind: "settings" } | { kind: "whimsy" } | { kind: "review"; tid: number; from?: Mode }
  | { kind: "look"; name: string; from?: Mode; hall?: true } | { kind: "look-editor"; name: string; view: "front" | "side" | "back"; from?: Mode; hall?: true }
  | { kind: "hall" } | { kind: "hall-pile" } | { kind: "store" } | { kind: "cast"; tab: "people" | "office" }
  | { kind: "help"; from: Mode; title: string; keys: Hint[] }
/** a detail-pane row, and what a click (or Enter, on the selected one) does with it */
export type Row = { segs: Seg[]; open?: () => void; ref?: unknown }
/** a choice an input cycles through with tab (the project a thread goes in, a template, …) */
export type Cycle = { name: string; values: { label: string; value: unknown }[]; i: number }
export type Prompt = { label: string; ed: Editor; submit: (s: string, picks: unknown[]) => void; cycles?: Cycle[]; focus: number }
/** one row of the finder: what it shows, what it is matched on, what picking it does */
export type Pick = { segs: Seg[]; text: string; run: () => void }
/** something you can do from a card: its key, what it says in the actions pane, what it does */
export type Action = { key: string; label: string; run: () => void }
/** the banter log: the last lines said in the room, oldest first, kept across restarts */
export type Said = { at: number; who: string; line: string }

// how the list cards are ordered (`s` sort, `g` group): kept across visits
export const CREW_GROUP_MODES = [null, ...CREW_GROUPS]
export type Item = ReturnType<typeof boardColumns>[number]["items"][number]
export const COL_SORTS: Sort<Item>[] = [{ name: "board", cmp: () => 0 }, { name: "title", cmp: (a, b) => a.title.localeCompare(b.title) }, { name: "who", cmp: (a, b) => (a.who ?? "~").localeCompare(b.who ?? "~") }]
export const TRAY_SORTS: Sort<data.Activity[number]>[] = [{ name: "newest", cmp: () => 0 }, { name: "thread", cmp: (a, b) => (a.thread_id ?? Infinity) - (b.thread_id ?? Infinity) }, { name: "who", cmp: (a, b) => (a.who ?? "~").localeCompare(b.who ?? "~") }]

/** everything the TUI holds between keys and frames: what it has read, what is open, what the pane last drew */
export class State {
  whim: WhimState = loadWhim(OFFICE)
  readonly world = SANDBOX ? toy() : null
  all: Agents = { ...EMPTY, note: "…" }
  ws: number | null = Number(readState(STATE)) || null
  // the wide room when the terminal is wide enough for it (`wide` is its width), else the rail room
  wide: number | null = null
  readonly rooms = new Map<number, RailRoom | WideRoom>()
  readonly threads = new Map<number, ThreadView>()
  mode: Mode = { kind: "home" }
  picked: number | null = null
  sel = 0
  tip = ""
  status = ""
  /** why each card's read came back empty (`data.reading`), by card: a poll still in flight for one card never sets the reason another shows */
  readonly readWhys = new Map<string, string>()
  /** the header's clickable spans, in 1-based columns, as last drawn */
  headHits: { from: number; to: number; go: () => void }[] = []
  crewTab = "all"
  crewSort = CREW_SORTS[0]!
  crewGroup: (typeof CREW_GROUP_MODES)[number] = null
  colSort = COL_SORTS[0]!
  /** the TICKETS column's open groups, by id */
  readonly expanded = new Set<number>()
  /** whether a person card shows its whole soul and persona; closed, it is one line under the conversation */
  cardOpen = false
  traySort = TRAY_SORTS[0]!
  input: Prompt | null = null
  // a card just opened: its cursor goes to the first row you can act on, once there is one
  snapSel = false
  confirm: { label: string; run: () => void } | null = null
  // the look card/editor's draft, not yet saved to looks.json; set on open, cleared on close/save
  lookDraft: LookOverride | null = null
  rolls = 0
  hall: Hall = loadHall(HALL)
  hallSeen = hallSignature(HALL)
  cast: Cast = loadCast(CAST)
  castSeen = castSignature(CAST)
  // the lit field of the cast view's lit row
  castCol = 0
  castRolls = 0
  store: Store = loadStore(STORE)
  storeSeen = hallSignature(STORE)
  // the pet card's draft (Nina's temperament, not yet saved to pets.json) and the preview row's clock
  petDraft: PetSetting | null = null
  previewTick = 0
  editBuf: Record<"front" | "side" | "back", string[]> | null = null
  editEntry: Record<"front" | "side" | "back", string[]> | null = null
  editCursor = { x: 0, y: 0 }
  editScroll = 0
  editMirror = true
  picker: { title: string; q: Editor; items: Pick[]; sel: number } | null = null
  reader: Reader | null = null
  /** a thread card's reply box: focused, it takes the keys; unfocused, the card's actions do. Its draft is the thread's, the reader's too */
  cardReply: { tid: number; ed: Editor; focused: boolean } | null = null
  cell: { w: number; h: number } | null = null
  kitty = process.env.OFFICE_GRAPHICS === "kitty"
  g!: Geometry
  frame: Frame | null = null
  sentImage = false
  rows: Row[] = []
  /** the floor's visible window: centred on the office zone while `follow`, fixed where a manual pan left it otherwise */
  viewport: Viewport = { x: 0, y: 0, w: 0, h: 0 }
  follow = true
  panned = false
  drag: { col: number; row: number } | null = null
  /** build mode's state, kept across a leave-and-reopen so you come back where you left it */
  build: Build | null = null
  // the room moved (re-render its frame); its art changed (resend the image)
  roomChanged = true
  imageDirty = true
  homeShown = false
  homeNow = loadFloor()
  // what the open card reads, fetched when it opens and on every refresh while it stays open
  archived: data.Archive | null = null
  feed: data.Activity = []
  stuck: data.Triage | null = null
  rack: data.Health | null = null
  /** the office corkboard: the crew's chatter to each other, newest first */
  cork: CorkNote[] = []
  /** everything waiting on you (`Server.Office.Needs`) by who acts; `needs` is every item, phone first */
  bySurface: data.Needs = { items: [], phone: [], machine: [], clipboard: [], uqbar: [], settled: [], counts: { phone: 0, machine: 0, clipboard: 0, uqbar: 0, settled: 0 } }
  needs: data.Need[] = []
  /** Scharlach's demerit ledger: ticks when a coworker's build goes red (the sheriff's workspace's triage) */
  ledger: Ledger = newLedger()
  /** the last banter line each seat said, so the canned fallback doesn't repeat itself */
  readonly recentBanter = new Map<string, string[]>()
  /** the office revision this TUI started on: when main's moves past it, R reloads */
  officeRev!: string | null | undefined
  /** the suggestion box: corkboard ideas the banter wrote in a coworker's voice (never a request), for you to file or throw out */
  ideas: CorkNote[] = []
  said: Said[] = (() => { try { return JSON.parse(readState(SAID) ?? "[]") as Said[] } catch { return [] } })()
  shelf: data.Memory | null = null
  tickets: data.BoardTicket[] = []
  card: data.WorkspaceCard | null = null
  settings: data.Settings | null = null
  /** the branch under review, and the notes not yet sent, kept per thread so leaving the screen loses none */
  review: data.Review | null = null
  readonly reviewNotes = new Map<number, data.ReviewNote[]>()
  lifeCard: LifeStatus | null = null
  dumpPages: data.DumpPage[] | null = null
  cal: data.Schedule[] | null = null
  board: data.Run[] = []
  trayRead = readState(TRAY)
  /** Uqbar's margin notes; `looks` fades each by the time the window was focused after it was first seen */
  notes: Note[] = []
  readonly looks = new Looks(Number(readState(LOOKED)) || 0)
  // a terminal that never reports focus is treated as always focused: notes fade from first sight
  focused = true
  lit: number | null = null
  viewed: { all: Agents; ws: number | null; v: Agents } | null = null
  paletteSeen = ""
  looksSeen = ""
  soulsSeen = ""
  petsSeen = ""
  petsNow: Pets | null = null
  // the last poll that answered: a restart's gap polls (ok:false) must not hide what changed across it
  lastOk: Agents = EMPTY
  lastOkNeeds: data.Need[] = []
  /** the feed rows already flown as aeroplanes */
  readonly flown = new Set<string>()
  trophies = parseTally(readState(TROPHY_FILE))
  readonly seenTreats = new Map<object, number>()
  wasAlarmed = false
  /** the posts whose aeroplane Argos caught, by `earmarkOf`: the thread shows them dog-eared */
  readonly earmarked = earmarksIn(readState(EARS))
  // the office's small talk: each line the server's banter wrote, once, as a balloon over its speaker
  readonly seenLines = new Set<string>()
  /** the operator's answers: a lobby post answering you is a balloon over its author, and a notification when a card covers the room */
  answered: Set<number> | null = null
  /** what an input held when ctrl+] left it, by its label, there again when it is asked again */
  readonly banked = new Map<string, string>()
  /**
   * Threads whose card shows the conversation instead of the running coworkers' activity timeline
   * (`tui/timeline.ts`, from the thread view's `activity`) — `c` flips, ⏎ steps into the session itself.
   */
  readonly talkView = new Set<number>()
  /** playerctl, polled every ~2s: feeds the wide room's stereo marquee + dance trigger; a failed run (no player) waits 30 s */
  playerBusy = false
  playerRetry = 0
  /** the cursor the last full draw left (an input's caret), re-set by a room-only draw so it does not hide it */
  paneCursor: string | null = null
  // what the pane last drew, for a click on it: where it starts, how wide its left side is, which
  // row and which action each of its lines shows
  acts: Action[] = []
  asel = 0
  pane = { top: 0, leftW: 0, room: 0, first: 0, rowAt: [] as (number | undefined)[], actAt: [] as (number | undefined)[] }
  /** how far a card whose rows have nothing to open is scrolled down; Infinity keeps a thread's tail in view */
  scroll = 0
  // the last keys pressed, for the Konami code
  keyLog: string[] = []
  zoom: { view: TerminalView; label: string; after?: () => void } | null = null
  /** the home's dump in the operator's own editor, in the office's tmux. Every save goes to the server, one PUT at
  *  a time per home (a write that lands mid-PUT is sent when it settles), and one the server didn't take is sent on
  *  the next write, leave, open or refresh: a file that differs from the server's page is never overwritten, it is sent —
  *  safe because the server keeps the page each save replaces. A session already open is reattached, never rewritten */
  readonly dumpSent = new Map<number, string>()
  readonly dumpSending = new Set<number>()
  readonly dumpAgain = new Set<number>()
  readonly dumpWatched = new Set<number>()
  readonly dumpFailedAt = new Map<number, number>()
  readonly dumpOldWatched = new Set<number>()
}
