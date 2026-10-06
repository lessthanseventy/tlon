// The office in a terminal: the room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes, the in-tray, the beacon, the rack, the bookshelf, the workspaces. A thread
// opens full-screen to read and answer; `/` finds anything. Runs on Linux and macOS: kitty
// graphics where the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { boardColumns, busiest, COLS, crewOf, needsYou, viewOf, type Act } from "../kit/crew"
import { ROLE, useRoles, type Role } from "../kit/palette"
import { shirtOf } from "../kit/sprites"
import { EMPTY, type Agents, type Thread, type ThreadView } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"
import { WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import * as data from "./data"
import { Editor, wrap } from "./editor"
import { rank } from "./fuzzy"
import { geometry, hitAt, kittyImage, measureFor, textLayer, type Geometry } from "./paint"
import { Reader } from "./reader"
import { enter, ESC, leave, line, out, query, tokenize, type Input, type Seg } from "./term"
import { rows as vtRows, TerminalView, type Target } from "./terminal"

type Mode =
  | { kind: "home" } | { kind: "crew" } | { kind: "notes" } | { kind: "boss" } | { kind: "archive" }
  | { kind: "person"; name: string } | { kind: "thread"; tid: number }
  | { kind: "column"; col: number } | { kind: "ticket"; id: number } | { kind: "calendar" }
  | { kind: "tray" } | { kind: "triage" } | { kind: "health" } | { kind: "memory" } | { kind: "card" }
/** a detail-pane row, and what a click (or Enter, on the selected one) does with it */
type Row = { segs: Seg[]; open?: () => void }
/** a choice an input cycles through with tab (the project a thread goes in, a template, …) */
type Cycle = { name: string; values: { label: string; value: unknown }[]; i: number }
type Prompt = { label: string; ed: Editor; submit: (s: string, picks: unknown[]) => void; cycles?: Cycle[] }
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

const readState = (p: string) => { try { return readFileSync(p, "utf8").trim() } catch { return "" } }
const writeState = (p: string, s: string) => { try { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, s) } catch { /* a read-only home: it just won't remember */ } }

let all: Agents = { ...EMPTY, note: "…" }
let ws: number | null = Number(readState(STATE)) || null
// the wide room when the terminal is wide enough for it (`wide` is its width), else the rail room
let wide: number | null = null
const rooms = new Map<number, RailRoom | WideRoom>()
const threads = new Map<number, ThreadView>()
let mode: Mode = { kind: "home" }, picked: number | null = null, sel = 0
let tip = "", status = ""
let input: Prompt | null = null
let confirm: { label: string; run: () => void } | null = null
let picker: { title: string; q: Editor; items: Pick[]; sel: number } | null = null
let reader: Reader | null = null
let cell: { w: number; h: number } | null = null, kitty = process.env.OFFICE_GRAPHICS === "kitty"
let g: Geometry, frame: Frame | null = null, sentImage = false, rows: Row[] = []
// the room moved (re-render its frame); its art changed (resend the image)
let roomChanged = true, imageDirty = true

// what the open card reads, fetched when it opens and on every refresh while it stays open
let archived: data.Archive | null = null, feed: data.Activity = [], stuck: data.Triage | null = null, rack: data.Health | null = null
let shelf: data.Memory | null = null, tickets: data.BoardTicket[] = [], card: data.WorkspaceCard | null = null
let trayRead = readState(TRAY)

const view = () => viewOf(all, ws)
const room = () => { const k = ws ?? 0; let r = rooms.get(k); if (!r) rooms.set(k, (r = wide ? new WideRoom(wide) : new RailRoom())); return r }
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
  const before = all
  all = await data.status()
  settleWorkspace()
  if (all.ok && before.ok) tellNews(before)
  const tid = openThread()
  await Promise.all([tid !== null ? loadThread(tid) : null, reader ? reader.reload() : null, loadCard(), loadFeed()])
  await chatter()
  draw()
}
/** what changed since the last look that you'd want to hear about even with the office in the back */
function tellNews(before: Agents) {
  const was = new Set(before.threads.filter(needsYou).map((t) => t.id))
  const fresh = all.threads.filter((t) => needsYou(t) && !was.has(t.id))
  if (fresh.length) out("\x07") // something new waits on you: the terminal's bell
  for (const t of fresh) notify(`#${t.id} ${t.title}`, t.prompt?.summary ?? `awaits ${t.awaiting}`)
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
  for (const b of await data.banter(ws)) {
    const k = `${b.at} ${b.agent}`
    if (heard.has(k)) continue
    heard.add(k)
    room().say(b.agent, b.line)
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
    case "ticket": case "column": tickets = (await data.board(w)) ?? tickets; break
    case "card": card = await data.workspaceCard(w); break
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
  mode = m; sel = 0; confirm = null; picker = null
  if (m.kind === "thread") picked = m.tid
  if (m.kind === "person") picked = crewOf(view()).find((c) => c.name === m.name)?.thread ?? null
  const tid = openThread()
  void Promise.all([tid !== null ? loadThread(tid) : null, loadCard()]).then(draw)
  draw()
}
/** Esc: a card back to home, home to nothing picked; `all` drops both at once */
function back(everything = false) {
  if (everything || mode.kind === "home") picked = null
  mode = { kind: "home" }; sel = 0; confirm = null; picker = null
}

function act(x: Act) {
  switch (x.kind) {
    case "thread": return open({ kind: "thread", tid: x.tid })
    case "ticket": return open({ kind: "ticket", id: x.id })
    case "person": return open({ kind: "person", name: x.name })
    case "column": return open({ kind: "column", col: x.col })
    case "notes": return open({ kind: "notes" })
    case "crew": return open({ kind: "crew" })
    case "boss": return open({ kind: "boss" })
    case "hire": return hire()
    case "pen": return newTicket()
    case "cat": room().pet(); return draw()
    case "calendar": return open({ kind: "calendar" })
    case "terminal": return void zoomInto(x.tid)
    case "archive": return open({ kind: "archive" })
    case "tray": return open({ kind: "tray" })
    case "beacon": return open({ kind: "triage" })
    case "rack": return open({ kind: "health" })
    case "dog": { const r = room(); if (r instanceof WideRoom) { r.patDog(); changed(); draw() } return }
    case "tv": { const r = room(); if (r instanceof WideRoom) { r.channel(); changed(); draw() } return }
  }
}

// ── writing: the inputs ─────────────────────────────────────────────────────────────────────────
function ask(label: string, submit: Prompt["submit"], opts: { multiline?: boolean; text?: string; cycles?: Cycle[] } = {}) {
  input = { label, ed: new Editor(opts.text ?? "", !!opts.multiline), submit, cycles: opts.cycles }
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
  for (const w of all.workspaces) picks.push({ segs: [{ s: "workspace ", fg: ROLE.inactive }, { s: w.name, fg: ROLE.body }], text: `workspace ${w.name}`, run: () => goWs(w.id) })
  for (const c of all.bench.filter((b) => b.workspace_id === ws)) picks.push({ segs: [{ s: "coworker ", fg: ROLE.inactive }, { s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}`, fg: ROLE.inactive }], text: `${c.name} ${c.archetype}`, run: () => open({ kind: "person", name: c.name }) })
  for (const [label, run] of VERBS) picks.push({ segs: [{ s: "do ", fg: ROLE.inactive }, { s: label, fg: ROLE.prose }], text: label, run })
  find("FIND — a thread, a workspace, a coworker, a verb", picks)
  const closed = await data.history()
  if (picker?.title.startsWith("FIND") && closed) {
    for (const t of closed) picker.items.push({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.inactive }, { s: `  closed ${t.at.slice(0, 10)}`, fg: ROLE.inactive }], text: `#${t.id} ${t.title} closed`, run: () => goThread(t.id, t.workspace_id) })
    draw()
  }
}
/** everything across the workspaces that waits on you, then what's being worked on */
function inbox() {
  const waiting = all.threads.filter(needsYou), live = all.threads.filter((t) => !needsYou(t) && t.live && !t.standing)
  const pick = (t: Thread, why: Seg): Pick => ({ segs: [tidSeg(t.id), { s: t.title, fg: ROLE.prose }, { s: `  ${wsName(t.workspace_id ?? null)} · `, fg: ROLE.inactive }, why], text: `#${t.id} ${t.title}`, run: () => goThread(t.id, t.workspace_id) })
  find(`INBOX — ${waiting.length} waiting on you, ${live.length} being worked`, [
    ...waiting.map((t) => pick(t, { s: t.prompt?.summary ?? `awaits ${t.awaiting}`, fg: ROLE.attention })),
    ...live.map((t) => pick(t, { s: t.lead ? `${t.lead} on it` : "running", fg: ROLE.live })),
  ])
}
/** the verbs the finder offers by name — the same ones the keys reach */
const VERBS: [string, () => void][] = [
  ["new thread", () => newThread()], ["new ticket", () => newTicket()], ["new note", () => newNote()], ["hire a coworker", () => hire()],
  ["in-tray: what just happened", () => open({ kind: "tray" })], ["triage: what is stuck", () => open({ kind: "triage" })],
  ["health: the service and its box", () => open({ kind: "health" })], ["memory: pinned facts and habits", () => open({ kind: "memory" })],
  ["workspaces", () => open({ kind: "boss" })], ["this workspace's settings and repos", () => open({ kind: "card" })],
  ["crew", () => open({ kind: "crew" })], ["calendar", () => open({ kind: "calendar" })], ["filing cabinet", () => open({ kind: "archive" })],
  ["inbox: everything waiting on you", () => inbox()],
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
const THREAD_KEYS = "r reply · enter terminal · g git · 1-9 answer · A approve · > advance · h hand off · M move · x close · D delete"

/** the verbs on a thread, wherever it is open (its card, a person's, the reader); true when one ran */
function threadKey(k: string, tid: number): boolean {
  const th = threadOf(tid)
  switch (k) {
    case "r": reply(tid); return true
    case "v": openReader(tid, false); return true
    case "t": case "enter": void zoomInto(tid); return true
    case "g": void zoomGit(tid); return true
    case "x": confirm = { label: `close #${tid} as done`, run: () => did(data.closeThread(tid)) }; draw(); return true
    case "D": confirm = { label: `delete #${tid} for good (its worktree goes too, if it loses nothing)`, run: () => { if (reader) closeReader(); back(); void did(data.deleteThread(tid)) } }; draw(); return true
    case "A": void did(data.approve(tid)); return true
    case ">": void did(data.advance(tid)); return true
    case "h": {
      const bench = view().bench
      find(`HAND #${tid} OFF TO`, bench.map((c) => ({ segs: [{ s: c.name, fg: shirtOf(c.archetype) }, { s: `  ${c.archetype ?? ""}${c.name === th?.lead ? " · leads it now" : ""}`, fg: ROLE.inactive }], text: c.name, run: () => { picker = null; void did(data.handOff(tid, c.name)) } })))
      return true
    }
    case "M": {
      const projects = view().projects
      find(`MOVE #${tid} TO PROJECT`, projects.map((p) => ({ segs: [{ s: p.name, fg: ROLE.prose }], text: p.name, run: () => { picker = null; void did(data.move(tid, p.id)) } })))
      return true
    }
  }
  if (/^[1-9]$/.test(k)) {
    const opt = th?.prompt?.options?.[Number(k) - 1]
    if (opt) { void did(data.post(tid, opt.key)); return true }
  }
  return false
}

// ── the detail pane ────────────────────────────────────────────────────────────────────────────
const dim = (s: string): Seg => ({ s, fg: ROLE.inactive }), plain = (s: string): Seg => ({ s, fg: ROLE.prose })
const key = (s: string): Seg => ({ s, fg: ROLE.key }), pink = (s: string): Seg => ({ s, fg: ROLE.attention })
const cols = () => process.stdout.columns ?? 80

function threadRows(th: Thread | undefined, tid: number): Row[] {
  const v = threads.get(tid), out: Row[] = []
  out.push({ segs: [key(`#${tid} `), plain(th?.title ?? "")] })
  out.push({ segs: [dim(`${th?.stage ?? "thread"}${th?.awaiting && th.stage ? ` · gated: ${th.awaiting}` : ""}${th?.lead ? ` · ${th.lead}` : ""}${th?.live ? " · running" : ""}`)] })
  if (th?.prompt) {
    out.push({ segs: [pink("asks: "), plain(th.prompt.summary)] })
    th.prompt.options?.forEach((o, i) => out.push({ segs: [key(` ${i + 1} `), plain(o.label)], open: () => did(data.post(tid, o.key)) }))
  } else if (th?.awaiting) out.push({ segs: [pink(`awaits ${th.awaiting}${th.stage ? " — A approves" : ""}`)] })
  // the conversation's tail, wrapped, as much as fits; `v` reads the whole of it
  const room = DETAIL - 1 - out.length, tail: Row[] = []
  for (const m of [...(v?.messages ?? [])].reverse()) {
    const lines = wrap(`${m.author}: ${m.body}`, cols() - 4)
    const rowsOf = lines.map((l, i): Row => ({ segs: i ? [plain(`  ${l}`)] : [{ s: `${m.author}: `, fg: m.author === OPERATOR ? ROLE.attention : ROLE.key }, plain(l.slice(m.author.length + 2))] }))
    tail.unshift(...rowsOf)
    if (tail.length >= room) break
  }
  out.push(...tail.slice(-room))
  if (!v?.messages.length && v?.peek) for (const l of v.peek.split("\n").filter((x) => x.trim()).slice(-4)) out.push({ segs: [dim(l)] })
  return out
}
const ago = (at: string) => {
  const s = Math.max(0, (Date.now() - new Date(at).getTime()) / 1000)
  return s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`
}
const KIND: Record<string, string> = { message: "said", fact: "learned", issue: "raised", question: "asked", check_failed: "check failed", check_passed: "check passed", work_landed: "landed", stage_advanced: "advanced", handoff_opened: "handed off" }

function detail(): { title: string; rows: Row[]; keys: string } {
  const a = view()
  switch (mode.kind) {
    case "home": {
      const waiting = a.threads.filter(needsYou)
      if (!waiting.length) return { title: "HOME", rows: [{ segs: [dim("nothing waits on you. click someone, a sticky or the crew board; / finds anything,")] }, { segs: [dim("n starts a thread, tab walks the crew, [ ] the workspaces.")] }], keys: "/ find · i inbox · n new thread · tab crew · [ ] workspace · c crew · t tickets · w in-tray · ! triage · H health · b memory · W workspaces · q quit" }
      return {
        title: `WAITING ON YOU · ${waiting.length}`,
        rows: waiting.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), pink(`  ${t.prompt?.summary ?? `awaits ${t.awaiting}`}`)], open: () => openReader(t.id, false) })),
        keys: "j/k move · enter read · / find · i inbox · n new thread · tab crew · [ ] workspace · q quit",
      }
    }
    case "crew": {
      const crew = crewOf(a)
      return {
        title: `CREW · ${crew.length}`,
        rows: crew.map((c) => {
          const b = a.bench.find((x) => x.name === c.name), arch = a.archetypes.find((x) => x.name === c.archetype)
          const model = b?.model ? b.model.model : arch?.model?.split("/").pop() ?? ""
          return {
            segs: [{ s: c.status === "working" ? "● " : c.status === "waiting" ? "! " : "○ ", fg: c.status === "working" ? ROLE.live : c.status === "waiting" ? ROLE.attention : ROLE.inactive },
              { s: c.name.padEnd(10), fg: shirtOf(c.archetype) }, dim(`${c.manager ? "manager" : c.archetype ?? "?"}${c.lead ? " · lead" : ""}`.padEnd(18)), key(model.padEnd(16)), dim(`${b?.ask ?? ""}`.padEnd(6)),
              dim(c.thread !== null ? `#${c.thread} ${c.title}` : "on the bench")],
            open: () => open({ kind: "person", name: c.name }),
          }
        }),
        keys: "j/k move · enter open · + hire · m model · y ask/allow · - let go · esc back",
      }
    }
    case "person": {
      const name = mode.name
      const c = crewOf(a).find((x) => x.name === name), b = a.bench.find((x) => x.name === name)
      if (!c) return { title: name.toUpperCase(), rows: [{ segs: [dim("not in this office any more")] }], keys: "esc back" }
      const model = b?.model ? `${b.model.provider}/${b.model.model}` : `${a.archetypes.find((x) => x.name === c.archetype)?.model ?? "?"} (archetype's)`
      const head: Row = { segs: [{ s: c.name, fg: shirtOf(c.archetype), bold: true }, dim(`  ${c.manager ? "manager" : c.archetype ?? ""}${c.lead ? " · lead" : ""} · ${c.status} · ${model} · ${b?.ask ?? "ask (archetype's)"}`)] }
      const seatKeys = b ? " · m model · y ask/allow · - let go" : ""
      if (c.thread === null) return { title: name.toUpperCase(), rows: [head, { segs: [dim("on the bench")] }], keys: `tab next${seatKeys} · esc back` }
      return { title: name.toUpperCase(), rows: [head, ...threadRows(threadOf(c.thread), c.thread)], keys: `${THREAD_KEYS}${seatKeys} · tab next · esc back` }
    }
    case "thread": {
      const tid = mode.tid
      return { title: `THREAD #${tid}`, rows: threadRows(threadOf(tid), tid), keys: `v read all · ${THREAD_KEYS} · esc back` }
    }
    case "column": {
      const col = boardColumns(a)[mode.col]!
      return {
        title: `${col.name} · ${col.items.length}`,
        rows: col.items.map((it) => {
          const blocked = it.act.kind === "ticket" && (tickets.find((t) => t.id === (it.act as { id: number }).id)?.blocked_by.length ?? 0) > 0
          return {
            segs: [key(it.act.kind === "ticket" ? `#${it.act.id} ` : it.act.kind === "thread" ? `#${it.act.tid} ` : ""), plain(it.title), dim(`  ${it.stage}${it.who ? ` · ${it.who}` : ""}`), ...(it.asks ? [pink("  waiting on you")] : []), ...(blocked ? [pink("  ⊘ blocked")] : [])],
            open: () => act(it.act),
          }
        }),
        keys: `j/k move · enter open · ← → columns${mode.col === 0 ? " · n new ticket · J/K reorder" : ""} · esc back`,
      }
    }
    case "ticket": {
      const id = mode.id
      const tk = a.tickets.find((t) => t.id === id), full = tickets.find((t) => t.id === id)
      if (!tk) return { title: `TICKET #${id}`, rows: [{ segs: [dim("started or gone")] }], keys: "esc back" }
      const rows: Row[] = [{ segs: [plain(tk.title)] }, { segs: [dim(`${tk.priority} priority${tk.routed ? " · with the manager to staff" : ""}`)] },
        { segs: [key("s "), plain("send to the manager to staff")], open: () => did(data.ticketRoute(id)) },
        { segs: [key("enter "), plain("start it with the lead")], open: () => did(data.ticketStart(id)) }]
      for (const by of full?.blocked_by ?? []) rows.push({ segs: [pink("⊘ blocked by "), key(`#${by} `), plain(tickets.find((t) => t.id === by)?.title ?? "")], open: () => did(data.ticketUnblock(id, by)) })
      if (full?.body) for (const l of wrap(full.body, cols() - 4).slice(0, 6)) rows.push({ segs: [dim(l)] })
      return { title: `TICKET #${id}`, rows, keys: "s send to manager · enter start with lead · e edit title · b blocked by… · J/K reorder · d delete · esc back" }
    }
    case "calendar": {
      const now = new Date(), first = new Date(now.getFullYear(), now.getMonth(), 1).getDay(), days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
      const rows: Row[] = [{ segs: [dim("  Su  Mo  Tu  We  Th  Fr  Sa")] }]
      let week: Seg[] = [plain("    ".repeat(first))]
      for (let d = 1; d <= days; d++) {
        const cell = String(d).padStart(4)
        week.push(d === now.getDate() ? { s: cell, fg: ROLE.attention, bold: true } : d < now.getDate() ? dim(cell) : plain(cell))
        if ((first + d) % 7 === 0 || d === days) { rows.push({ segs: week }); week = [] }
      }
      rows.push({ segs: [dim("nothing scheduled yet")] })
      return { title: now.toLocaleString("en", { month: "long", year: "numeric" }).toUpperCase(), rows, keys: "esc back" }
    }
    case "archive": {
      if (!archived) return { title: "FILING CABINET", rows: [{ segs: [dim("opening the drawers…")] }], keys: "esc back" }
      const day = (s: string | null) => (s ? s.slice(0, 10) : "")
      const rows: Row[] = [{ segs: [key(`TICKETS DONE · ${archived.tickets.length}`)] }]
      for (const t of archived.tickets) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${day(t.closed_at)}`)] })
      rows.push({ segs: [key(`THREADS CLOSED · ${archived.threads.length}`)] })
      for (const t of archived.threads) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${t.stage ?? ""} ${day(t.at)}`)], open: () => openReader(t.id, false) })
      return { title: "FILING CABINET", rows, keys: "j/k move · enter read a thread (replying reopens it) · esc back" }
    }
    case "notes":
      return { title: `NOTES · ${a.notes.length}`, rows: a.notes.map((n) => ({ segs: [{ s: `${n.author}: `, fg: shirtOf(a.bench.find((b) => b.name === n.author)?.archetype) }, plain(n.body.replace(/\s+/g, " "))] })), keys: "j/k move · n new note · esc back" }
    case "tray": {
      const rows = feed.map((x): Row => ({
        segs: [dim(ago(x.at).padStart(4) + " "), x.thread_id ? key(`#${x.thread_id} `) : dim(""), { s: `${x.who ?? ""} ${KIND[x.kind] ?? x.kind.replace(/_/g, " ")} `, fg: x.kind === "issue" || x.kind === "check_failed" ? ROLE.alarm : x.kind === "question" ? ROLE.attention : ROLE.inactive }, plain(x.text.replace(/\s+/g, " "))],
        open: x.thread_id ? () => openReader(x.thread_id!, false) : undefined,
      }))
      return { title: `IN-TRAY · what just happened in ${wsName()}`, rows: rows.length ? rows : [{ segs: [dim("nothing yet")] }], keys: "j/k move · enter read the thread · esc back" }
    }
    case "triage": {
      if (!stuck) return { title: "TRIAGE", rows: [{ segs: [dim("looking…")] }], keys: "esc back" }
      const rows: Row[] = []
      const section = (name: string, c: data.Capped<data.Stuck>) => {
        if (!c.shown.length) return
        rows.push({ segs: [key(name)] })
        for (const s of c.shown) rows.push({ segs: [key(`  #${s.thread_id} `), plain(s.title), pink(`  ${s.text}`)], open: () => openReader(s.thread_id, false) })
        if (c.more) rows.push({ segs: [dim(`  +${c.more} more`)] })
      }
      section("BLOCKERS — open issues", stuck.blockers); section("FAILED CHECKS", stuck.failed_checks); section("NOBODY LEADS", stuck.unled)
      return { title: `TRIAGE · ${stuck.count} stuck in ${wsName()}`, rows: rows.length ? rows : [{ segs: [dim("nothing is stuck. the beacon is dark.")] }], keys: "j/k move · enter read the thread · esc back" }
    }
    case "health": {
      if (!rack) return { title: "THE RACK", rows: [{ segs: [dim("probing…")] }], keys: "esc back" }
      const ok = (b: boolean, s: string): Row => ({ segs: [{ s: b ? "● " : "✕ ", fg: b ? ROLE.live : ROLE.alarm }, plain(s)] })
      const up = rack.up_s < 3600 ? `${Math.floor(rack.up_s / 60)}m` : rack.up_s < 86400 ? `${Math.floor(rack.up_s / 3600)}h` : `${Math.floor(rack.up_s / 86400)}d`
      const rows: Row[] = [
        ...rack.problems.map((p) => ({ segs: [pink("! "), plain(p)] })),
        ok(true, `tlon ${rack.version}, up ${up}`), ok(rack.db, "the database answers"), ok(rack.jobs, rack.jobs ? "the job queue runs (staffing, sweeps, schedules)" : "no job queue on this node"),
        ok(rack.failed_jobs === 0, `${rack.failed_jobs} failed job(s) today`), ok(rack.tmux, "tmux is there for the coworkers"),
        { segs: [dim(`disk ${rack.disk_pct ?? "?"}% · memory ${rack.mem_pct ?? "?"}% · load ${rack.load ?? "?"}`)] },
      ]
      return { title: `THE RACK · ${rack.state === "ok" ? "all green" : "needs a look"}`, rows, keys: "esc back" }
    }
    case "memory": {
      if (!shelf) return { title: "MEMORY", rows: [{ segs: [dim("taking the books down…")] }], keys: "esc back" }
      const rows: Row[] = [{ segs: [dim(`${shelf.coverage.facts} facts, ${shelf.coverage.embedded} embedded · pinned ${shelf.coverage.pinned_count} (~${shelf.coverage.pinned_tokens} of ${shelf.coverage.budget} tokens)`)] }]
      rows.push({ segs: [key(`HABITS TO REVIEW · ${shelf.habits.length}`)] })
      for (const h of shelf.habits) rows.push({ segs: [dim(`  ${h.by ?? "?"}: `), plain(h.text)], open: () => void 0 })
      rows.push({ segs: [key(`PINNED — every session loads these · ${shelf.pinned.length}`)] })
      for (const f of shelf.pinned) rows.push({ segs: [dim(`  ${f.id} `), plain(f.text.replace(/\s+/g, " "))], open: () => void 0 })
      return { title: "MEMORY", rows, keys: "j/k move · on a habit: a approve, r reject · on a pinned fact: d forget · esc back" }
    }
    case "boss": {
      const rows: Row[] = [{ segs: [plain(all.awaiting ? `${all.awaiting} thread(s) wait on you across the office` : "nothing waits on you")] }]
      for (const w of all.workspaces) {
        const n = all.threads.filter((t) => t.workspace_id === w.id && needsYou(t)).length, s = all.triage[String(w.id)] ?? 0
        rows.push({ segs: [key(w.id === ws ? "▸ " : "  "), plain(w.name.padEnd(16)), n ? pink(`${n} waiting  `) : dim(""), s ? pink(`${s} stuck`) : dim("")], open: () => goWs(w.id) })
      }
      return { title: "WORKSPACES", rows, keys: "j/k move · enter switch · n new workspace · e this one's settings · d close it · + hire · esc back" }
    }
    case "card": {
      if (!card) return { title: "SETTINGS", rows: [{ segs: [dim("reading…")] }], keys: "esc back" }
      const rows: Row[] = [
        { segs: [dim("type  "), plain(card.type), dim("   scope  "), plain(card.scope), dim("   icon  "), plain(card.icon ?? "—")] },
        { segs: [key(`REPOS · ${card.repos.length}`)] },
        ...card.repos.map((r): Row => ({ segs: [plain(`  ${r.path}`), dim(r.remote ? `  ${r.remote}` : "")], open: () => void 0 })),
      ]
      return { title: `${card.name.toUpperCase()} · SETTINGS`, rows, keys: "t type · s scope · i icon · + add a repo · - remove the selected repo · esc back" }
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
  g = { ...(wide ? geometry(wide, WIDE_H, colsN, rowsN, DETAIL + 3, cell, kitty) : geometry(W, H, colsN, rowsN, DETAIL + 3, cell, kitty)), row: 1 }
  frame = null; sentImage = false
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
}

function draw() {
  if (!g || zoom) return
  const colsN = cols(), termRows = process.stdout.rows ?? 40
  if (reader) {
    if (picker || confirm) { out(`${ESC}[?25l` + drawOverlay(colsN, termRows)); return }
    out(reader.draw(colsN, termRows, threadOf(reader.tid), `${THREAD_KEYS.replace("enter terminal", "t terminal")} · pgup/pgdn scroll · esc back`))
    return
  }
  const a = view()
  let o = `${ESC}[?2026h${ESC}[?25l`
  // header: the workspace, and what waits elsewhere
  const elsewhere = all.threads.filter((t) => t.workspace_id !== ws && needsYou(t)).length
  o += `${ESC}[1;1H` + line([{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(), fg: ROLE.body, bold: true }, key(" › "),
    ...(all.ok ? [] : [{ s: `  ${all.note ?? "channel down"}`, fg: ROLE.alarm }]), ...(elsewhere ? [pink(`  ! ${elsewhere} elsewhere`)] : []),
    ...(all.health?.state === "warn" ? [{ s: `  ⚠ ${all.health.problems[0]}`, fg: ROLE.alarm }] : [])], colsN)
  // the room
  const room0 = room()
  const fresh = !frame
  if (fresh || roomChanged) { frame = room0.render(a, { picked, armed: null, person: mode.kind === "person" ? mode.name : null, tray: unread() }, measureFor(g)); roomChanged = false }
  if (g.kitty && (!sentImage || fresh || imageDirty)) { o += kittyImage(frame!, g); sentImage = true; imageDirty = false }
  if (!g.kitty) textLayer(frame!, g).forEach((l, i) => { o += `${ESC}[${g.row + 1 + i};${g.col + 1}H${l}` })
  // the tip line: what the pointer is over, or what just happened
  const tipRow = g.row + g.rows + 1
  o += `${ESC}[${tipRow};1H` + line([tip ? dim(` ${tip.split("\n").join(" · ")}`) : status ? key(` ${status}`) : dim("")], colsN)
  out(o + drawPane(tipRow + 1, colsN, termRows) + `${ESC}[?2026l`)
}

/** the detail pane from row `top` to the foot: the finder, a multi-line input, or the mode's card */
function drawPane(top: number, colsN: number, termRows: number): string {
  let o = ""
  const body = Math.max(1, termRows - top - 1)
  let title: string, keys: string, segRows: Row[], cursor: { r: number; c: number } | null = null
  if (picker) {
    const shown = rank(picker.q.text, picker.items, (p) => p.text)
    picker.sel = Math.min(picker.sel, Math.max(0, shown.length - 1))
    title = `${picker.title}: ${picker.q.text}`
    segRows = shown.map((p) => ({ segs: p.segs, open: p.run }))
    keys = "type to narrow · ↑↓ move · enter pick · esc close"
    cursor = { r: -1, c: title.length + 1 }
    sel = picker.sel
  } else if (input?.ed.multiline) {
    const v = input.ed.view(colsN - 6, body - 2)
    title = input.label
    segRows = [{ segs: cyclesSegs(input) }, ...v.rows.map((r) => ({ segs: [pink(" ▌ "), plain(r)] }))]
    keys = `enter done · alt-enter newline${input.cycles?.length ? " · tab/shift-tab choose" : ""} · esc cancel`
    cursor = { r: v.cursor.r + 1, c: v.cursor.c + 3 }
  } else {
    const d = detail()
    title = d.title; keys = d.keys; segRows = d.rows
  }
  rows = segRows
  o += `${ESC}[${top};1H` + line([{ s: ` ${title} `, fg: ROLE.ground, bg: picker || input ? ROLE.attention : ROLE.key }, dim(" " + "─".repeat(Math.max(0, colsN - title.length - 3)))], colsN)
  const selectable = rows.some((r) => r.open) && !input
  if (sel >= rows.length) sel = Math.max(0, rows.length - 1)
  const first = cursor && input ? 0 : Math.max(0, Math.min(sel - Math.floor((body - 1) / 2), rows.length - (body - 1)))
  for (let i = 0; i < body - 1; i++) {
    const r = rows[first + i]
    const mark = r && selectable && first + i === sel && mode.kind !== "thread" && mode.kind !== "person" ? key("▸ ") : plain("  ")
    o += `${ESC}[${top + 1 + i};1H` + line(r ? [mark, ...r.segs] : [], colsN)
  }
  // the foot: the keys that work here, the line you are typing, or a confirm
  const one = input && !input.ed.multiline ? input : null
  o += `${ESC}[${termRows};1H` + line(one ? [pink(` ${one.label}: `), plain(one.ed.text), ...(one.cycles?.length ? [dim("   tab: "), ...cyclesSegs(one)] : [])] : confirm ? [pink(` ${confirm.label} (y/n)`)] : [dim(` ${keys}`)], colsN)
  if (one) {
    const pre = [...` ${one.label}: `].length
    o += `${ESC}[${termRows};${pre + one.ed.col + 1}H${ESC}[?25h`
  } else if (cursor && cursor.r >= 0) o += `${ESC}[${top + 1 + cursor.r};${cursor.c + 3}H${ESC}[?25h`
  else if (cursor) o += `${ESC}[${top};${cursor.c + 1}H${ESC}[?25h`
  return o
}
const cyclesSegs = (i: Prompt): Seg[] => (i.cycles ?? []).flatMap((c) => [dim(`${c.name} `), key(`‹${c.values[c.i]!.label}› `)])

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
    const c = i.cycles[k === "tab" ? 0 : i.cycles.length - 1]!
    c.i = (c.i + 1) % c.values.length
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

/** a key on the open card that only means something there; true when it did */
function cardKey(k: string): boolean {
  const a = view(), w = ws
  switch (mode.kind) {
    case "crew": case "person": {
      const name = mode.kind === "person" ? mode.name : crewOf(a)[sel]?.name
      const b = a.bench.find((x) => x.name === name)
      if (k === "+") { hire(); return true }
      if (!b || w === null) return false
      if (k === "m") {
        const models = [{ label: `the archetype's (${a.archetypes.find((x) => x.name === b.archetype)?.model ?? "?"})`, value: "inherit" }, ...a.models.map((m) => ({ label: `${m.key}  ${m.thinking} · ${m.harness}`, value: m.key }))]
        find(`${b.name.toUpperCase()}'S MODEL`, models.map((m) => ({ segs: [plain(m.label)], text: m.label, run: () => { picker = null; void did(data.retarget(w, b.agent_id, { model: m.value })) } })))
        return true
      }
      if (k === "y") { void did(data.retarget(w, b.agent_id, { ask: b.ask === "allow" ? "ask" : "allow" })); return true }
      if (k === "-") { confirm = { label: `let ${b.name} go from ${wsName()} (the agent itself stays)`, run: () => did(data.unseat(b.seat_id, b.name)) }; draw(); return true }
      return false
    }
    case "column":
      if (mode.col === 0 && k === "n") { newTicket(); return true }
      if (mode.col === 0 && (k === "J" || k === "K")) {
        const it = boardColumns(a)[0]!.items[sel]
        if (it?.act.kind === "ticket") { void did(data.ticketReorder(it.act.id, k === "K" ? "up" : "down")).then(() => { sel = Math.max(0, Math.min(sel + (k === "K" ? -1 : 1), rows.length - 1)); draw() }); return true }
      }
      return false
    case "ticket": {
      const id = mode.id, tk = a.tickets.find((t) => t.id === id)
      if (!tk) return false
      if (k === "s") { void did(data.ticketRoute(id)); return true }
      if (k === "enter" && sel < 4) { void did(data.ticketStart(id)); return true }
      if (k === "e") { ask(`ticket #${id} title`, (s) => { if (s.trim()) did(data.ticketPatch(id, { title: s.trim() })) }, { text: tk.title }); return true }
      if (k === "d") { confirm = { label: `delete ticket #${id}`, run: () => { back(); void did(data.ticketDelete(id)) } }; draw(); return true }
      if (k === "J" || k === "K") { void did(data.ticketReorder(id, k === "K" ? "up" : "down")); return true }
      if (k === "b") {
        const others = tickets.filter((t) => t.id !== id && t.status !== "done")
        find(`#${id} IS BLOCKED BY`, others.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), dim(`  ${t.status}`)], text: `#${t.id} ${t.title}`, run: () => { picker = null; void did(data.ticketBlock(id, t.id)) } })))
        return true
      }
      return false
    }
    case "notes": if (k === "n") { newNote(); return true } return false
    case "memory": {
      if (!shelf) return false
      const h = shelf.habits[sel - 2], f = shelf.pinned[sel - 3 - shelf.habits.length]
      if (h && (k === "a" || k === "r")) { void did(data.habit(h.id, k === "a" ? "approve" : "reject")).then(loadCard).then(draw); return true }
      if (f && k === "d") { confirm = { label: `forget "${f.text.slice(0, 50)}"`, run: () => void did(data.forget(f.id)).then(loadCard).then(draw) }; draw(); return true }
      return false
    }
    case "boss": {
      if (k === "n") {
        const tpl = ["code", "life", "blank"].map((t) => ({ label: t, value: t }))
        ask("new workspace — its name", (s, [t]) => { if (s.trim()) did(data.workspaceNew(s.trim(), t as string)) }, { cycles: [{ name: "from", values: tpl, i: 0 }] })
        return true
      }
      if (k === "e") { open({ kind: "card" }); return true }
      if (k === "d" && w !== null) { confirm = { label: `close ${wsName()} (its threads move to another workspace)`, run: () => void did(data.workspaceDelete(w)) }; draw(); return true }
      if (k === "+") { hire(); return true }
      return false
    }
    case "card": {
      if (!card || w === null) return false
      const ring = (xs: string[], x: string) => xs[(xs.indexOf(x) + 1) % xs.length]!
      if (k === "t") { void did(data.workspaceEdit(w, { type: ring(["code", "life", "blank"], card.type) })).then(loadCard).then(draw); return true }
      if (k === "s") { void did(data.workspaceEdit(w, { scope: ring(["project", "machine"], card.scope) })).then(loadCard).then(draw); return true }
      if (k === "i") { ask("icon", (s) => void did(data.workspaceEdit(w, { icon: s.trim() })).then(loadCard).then(draw), { text: card.icon ?? "" }); return true }
      if (k === "+") { ask("add a repo — its path", (s) => { if (s.trim()) void did(data.repoAdd(w, s.trim())).then(loadCard).then(draw) }); return true }
      const repo = card.repos[sel - 2]
      if (k === "-" && repo) { confirm = { label: `remove ${repo.path} from ${card.name}`, run: () => void did(data.repoRemove(repo.id)).then(loadCard).then(draw) }; draw(); return true }
      return false
    }
  }
  return false
}

function onKey(k: string) {
  if (picker) return pickerKey(k)
  if (input) return inputKey(k)
  if (confirm) { const c = confirm; confirm = null; if (k === "y") c.run(); return draw() }
  if (reader) {
    const r = reader.key(k, Math.max(1, (process.stdout.rows ?? 24) - 6))
    if (r === "leave") return closeReader()
    if (r === "pass") { if (k !== "r" && threadKey(k === "enter" ? "" : k, reader.tid)) return; return }
    if (r !== "done") void r.then(draw)
    return draw()
  }
  if (cardKey(k)) return
  const tid = openThread()
  if (tid !== null && k !== "enter" && threadKey(k, tid)) return
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
    case "j": case "down": sel = Math.min(sel + 1, rows.length - 1); return draw()
    case "k": case "up": sel = Math.max(sel - 1, 0); return draw()
    case "left": case "right":
      if (mode.kind === "column") return open({ kind: "column", col: (mode.col + (k === "right" ? 1 : COLS.length - 1)) % COLS.length })
      return
    case "enter":
      if ((mode.kind === "thread" || mode.kind === "person") && tid !== null) return void zoomInto(tid)
      return rows[sel]?.open?.()
    case "/": case "ctrl-k": return void finder()
    case "i": return inbox()
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
    case "W": return open({ kind: "boss" })
    case "p": room().pet(); return
  }
}
function onPaste(text: string) {
  if (picker) { picker.q.insert(text); return draw() }
  if (input) { input.ed.insert(text); return draw() }
  if (reader) { reader.paste(text); return draw() }
}

function onMouse(m: Extract<Input, { t: "mouse" }>) {
  if (!frame || !g || reader) return
  const h = hitAt(frame, g, m.col, m.row)
  if (m.motion) { const t = h?.tip ?? ""; if (t !== tip) { tip = t; draw() } return }
  if (!m.press || m.button !== 0) return
  const inRoom = m.row - 1 >= g.row && m.row - 1 < g.row + g.rows
  if (h) return act(h.act)
  // a click on bare floor clears the slate, as on the desktop
  if (inRoom) { back(true); roomChanged = true; return draw() }
  const top = g.row + g.rows + 3, i = m.row - top
  const body = (process.stdout.rows ?? 40) - top
  const first = Math.max(0, Math.min(sel - Math.floor((body - 1) / 2), rows.length - (body - 1)))
  const r = rows[first + i]
  if (i >= 0 && r?.open) { sel = first + i; r.open() }
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
  setInterval(refresh, 10_000)
  setInterval(() => { if (followPalette()) { frame = null; draw() } }, 1000)
  // the room's clock: 10 Hz, drawn only when it changed
  setInterval(() => { if (!reader && room().step(view())) { changed(); draw() } }, 100)
}
main()
