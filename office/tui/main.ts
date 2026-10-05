// The office in a terminal: the rail room up top, a tip line, and a fixed detail pane under it that
// swaps with what you click or key to — the crew, a person and their thread, the board's columns,
// a ticket, the notes. Talk to a thread (reply, answer its prompt, close it) and hand out tickets;
// hiring and configuring stay on the desktop for now. Runs on Linux and macOS: kitty graphics where
// the terminal has them (ghostty, kitty, WezTerm), half blocks where it does not.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import type { Frame } from "../kit/canvas"
import { boardColumns, busiest, COLS, crewOf, needsYou, viewOf, type Act } from "../kit/crew"
import { ROLE } from "../kit/palette"
import { shirtOf } from "../kit/sprites"
import { EMPTY, type Agents, type Thread, type ThreadView } from "../kit/types"
import { H, RailRoom, W } from "../rooms/rail"
import { WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import * as data from "./data"
import { geometry, hitAt, kittyImage, measureFor, textLayer, type Geometry } from "./paint"
import { enter, ESC, leave, line, out, query, tokenize, type Input, type Seg } from "./term"

type Mode =
  | { kind: "home" } | { kind: "crew" } | { kind: "notes" } | { kind: "boss" }
  | { kind: "person"; name: string } | { kind: "thread"; tid: number }
  | { kind: "column"; col: number } | { kind: "ticket"; id: number } | { kind: "calendar" }
/** a detail-pane row, and what a click (or Enter, on the selected one) does with it */
type Row = { segs: Seg[]; open?: () => void }

const DETAIL = 14 // the detail pane's rows, title included: fixed, so nothing below the room moves
const STATE = join(process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"), "tlon/office-workspace")

let all: Agents = { ...EMPTY, note: "…" }
let ws: number | null = (() => { try { const n = Number(readFileSync(STATE, "utf8").trim()); return n > 0 ? n : null } catch { return null } })()
// the wide room when the terminal is wide enough for it (`wide` is its width), else the rail room
let wide: number | null = null
const rooms = new Map<number, RailRoom | WideRoom>()
const threads = new Map<number, ThreadView>()
let mode: Mode = { kind: "home" }, picked: number | null = null, sel = 0
let tip = "", status = ""
let input: { label: string; text: string; submit: (s: string) => void } | null = null
let confirm: { label: string; run: () => void } | null = null
let cell: { w: number; h: number } | null = null, kitty = process.env.OFFICE_GRAPHICS === "kitty"
let g: Geometry, frame: Frame | null = null, sentImage = false, rows: Row[] = []
// the room moved (re-render its frame); its art changed (resend the image)
let roomChanged = true, imageDirty = true

const view = () => viewOf(all, ws)
const room = () => { const k = ws ?? 0; let r = rooms.get(k); if (!r) rooms.set(k, (r = wide ? new WideRoom(wide) : new RailRoom())); return r }
const threadOf = (id: number | null) => (id === null ? undefined : all.threads.find((t) => t.id === id))
const wsName = () => all.workspaces.find((w) => w.id === ws)?.name ?? "—"

function choose(id: number | null) {
  ws = id
  try { mkdirSync(dirname(STATE), { recursive: true }); writeFileSync(STATE, id === null ? "" : String(id)) } catch { /* a read-only home: it just won't remember */ }
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
  choose(list[(i + d + list.length) % list.length]!.id)
  back(true); frame = null; draw()
}

async function refresh() {
  const before = all.awaiting
  all = await data.status()
  settleWorkspace()
  if (all.ok && all.awaiting > before) out("\x07") // something new waits on you: the terminal's bell
  const tid = openThread()
  if (tid !== null) await loadThread(tid)
  draw()
}
async function loadThread(tid: number) { const v = await data.thread(tid); if (v) threads.set(tid, v) }
/** after a write: say what happened, then look again */
async function did(p: Promise<string>) { status = await p; await refresh() }

/** the thread the detail pane is showing, if any */
function openThread(): number | null {
  if (mode.kind === "thread") return mode.tid
  if (mode.kind === "person") { const name = mode.name, p = crewOf(view()).find((c) => c.name === name); return p?.thread ?? null }
  return null
}
function open(m: Mode) {
  mode = m; sel = 0; confirm = null
  if (m.kind === "thread") picked = m.tid
  if (m.kind === "person") picked = crewOf(view()).find((c) => c.name === m.name)?.thread ?? null
  const tid = openThread()
  if (tid !== null) loadThread(tid).then(draw)
  draw()
}
/** Esc: a card back to home, home to nothing picked; `all` drops both at once */
function back(everything = false) {
  if (everything || mode.kind === "home") picked = null
  mode = { kind: "home" }; sel = 0; confirm = null
}

function act(x: Act) {
  switch (x.kind) {
    case "thread": return open({ kind: "thread", tid: x.tid })
    case "ticket": return open({ kind: "ticket", id: x.id })
    case "person": return open({ kind: "person", name: x.name })
    case "column": return open({ kind: "column", col: x.col })
    case "notes": return open({ kind: "notes" })
    case "crew": return open({ kind: "crew" })
    case "boss": case "hire": return open({ kind: "boss" })
    case "pen": return newTicket()
    case "cat": room().pet(); return draw()
    case "calendar": return open({ kind: "calendar" })
  }
}
function newTicket() {
  if (ws === null) return
  const w = ws
  input = { label: "new ticket", text: "", submit: (s) => { if (s.trim()) did(data.ticketFile(w, s.trim())) } }
  draw()
}
function reply(tid: number) {
  input = { label: `reply to #${tid}`, text: "", submit: (s) => { if (s.trim()) did(data.post(tid, s.trim())) } }
  draw()
}

// ── the detail pane ────────────────────────────────────────────────────────────────────────────
const dim = (s: string): Seg => ({ s, fg: ROLE.inactive }), plain = (s: string): Seg => ({ s, fg: ROLE.prose })
const key = (s: string): Seg => ({ s, fg: ROLE.key }), pink = (s: string): Seg => ({ s, fg: ROLE.attention })

function threadRows(th: Thread | undefined, tid: number): Row[] {
  const v = threads.get(tid), out: Row[] = []
  out.push({ segs: [key(`#${tid} `), plain(th?.title ?? "")] })
  out.push({ segs: [dim(`${th?.stage ?? "thread"}${th?.lead ? ` · ${th.lead}` : ""}${th?.live ? " · running" : ""}`)] })
  if (th?.prompt) {
    out.push({ segs: [pink("asks: "), plain(th.prompt.summary)] })
    th.prompt.options?.forEach((o, i) => out.push({ segs: [key(` ${i + 1} `), plain(o.label)], open: () => did(data.post(tid, o.key)) }))
  } else if (th?.awaiting) out.push({ segs: [pink(`awaits ${th.awaiting}`)] })
  const msgs = (v?.messages ?? []).slice(-(DETAIL - 1 - out.length))
  for (const m of msgs) out.push({ segs: [{ s: `${m.author}: `, fg: m.author === "andrew" ? ROLE.attention : ROLE.key }, plain(m.body.replace(/\s+/g, " "))] })
  if (!msgs.length && v?.peek) for (const l of v.peek.split("\n").filter((x) => x.trim()).slice(-4)) out.push({ segs: [dim(l)] })
  return out
}

function detail(): { title: string; rows: Row[]; keys: string } {
  const a = view()
  switch (mode.kind) {
    case "home": {
      const waiting = a.threads.filter(needsYou)
      if (!waiting.length) return { title: "HOME", rows: [{ segs: [dim("nothing waits on you. click someone, a sticky or the crew board;")] }, { segs: [dim("tab walks the crew, [ ] the workspaces.")] }], keys: "tab crew · [ ] workspace · c crew · t tickets · n new ticket · o notes · a calendar · q quit" }
      return {
        title: `WAITING ON YOU · ${waiting.length}`,
        rows: waiting.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), pink(`  ${t.prompt?.summary ?? `awaits ${t.awaiting}`}`)], open: () => open({ kind: "thread", tid: t.id }) })),
        keys: "j/k move · enter open · tab crew · [ ] workspace · q quit",
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
              { s: c.name.padEnd(10), fg: shirtOf(c.archetype) }, dim(`${c.manager ? "manager" : c.archetype ?? "?"}${c.lead ? " · lead" : ""}`.padEnd(18)), key(model.padEnd(16)),
              dim(c.thread !== null ? `#${c.thread} ${c.title}` : "on the bench")],
            open: () => open({ kind: "person", name: c.name }),
          }
        }),
        keys: "j/k move · enter open · esc back",
      }
    }
    case "person": {
      const name = mode.name
      const c = crewOf(a).find((x) => x.name === name)
      if (!c) return { title: name.toUpperCase(), rows: [{ segs: [dim("not in this office any more")] }], keys: "esc back" }
      const head: Row = { segs: [{ s: c.name, fg: shirtOf(c.archetype), bold: true }, dim(`  ${c.manager ? "manager" : c.archetype ?? ""}${c.lead ? " · lead" : ""} · ${c.status}`)] }
      if (c.thread === null) return { title: name.toUpperCase(), rows: [head, { segs: [dim("on the bench")] }], keys: "tab next · esc back" }
      return { title: name.toUpperCase(), rows: [head, ...threadRows(threadOf(c.thread), c.thread)], keys: "r reply · 1-9 answer · x close thread · tab next · esc back" }
    }
    case "thread": {
      const tid = mode.tid
      return { title: `THREAD #${tid}`, rows: threadRows(threadOf(tid), tid), keys: "r reply · 1-9 answer · x close thread · esc back" }
    }
    case "column": {
      const col = boardColumns(a)[mode.col]!
      return {
        title: `${col.name} · ${col.items.length}`,
        rows: col.items.map((it) => ({
          segs: [key(it.act.kind === "ticket" ? `#${it.act.id} ` : it.act.kind === "thread" ? `#${it.act.tid} ` : ""), plain(it.title), dim(`  ${it.stage}${it.who ? ` · ${it.who}` : ""}`), ...(it.asks ? [pink("  waiting on you")] : [])],
          open: () => act(it.act),
        })),
        keys: "j/k move · enter open · ← → columns · esc back",
      }
    }
    case "ticket": {
      const id = mode.id
      const tk = a.tickets.find((t) => t.id === id)
      if (!tk) return { title: `TICKET #${id}`, rows: [{ segs: [dim("started or gone")] }], keys: "esc back" }
      return {
        title: `TICKET #${id}`,
        rows: [{ segs: [plain(tk.title)] }, { segs: [dim(`${tk.priority} priority${tk.routed ? " · with the manager to staff" : ""}`)] },
          { segs: [key("s "), plain("send to the manager to staff")], open: () => did(data.ticketRoute(id)) },
          { segs: [key("enter "), plain("start it with the lead")], open: () => did(data.ticketStart(id)) }],
        keys: "s send to manager · enter start with lead · esc back",
      }
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
    case "notes":
      return { title: `NOTES · ${a.notes.length}`, rows: a.notes.map((n) => ({ segs: [{ s: `${n.author}: `, fg: shirtOf(a.bench.find((b) => b.name === n.author)?.archetype) }, plain(n.body.replace(/\s+/g, " "))] })), keys: "j/k move · esc back" }
    case "boss": {
      const rows: Row[] = [{ segs: [plain(a.awaiting ? `${a.awaiting} thread(s) here wait on you` : "nothing here waits on you")] }]
      for (const w of all.workspaces) {
        const n = all.threads.filter((t) => t.workspace_id === w.id && needsYou(t)).length
        rows.push({ segs: [key(w.id === ws ? "▸ " : "  "), plain(w.name.padEnd(16)), n ? pink(`${n} waiting`) : dim("")], open: () => { choose(w.id); back(true); frame = null; draw() } })
      }
      rows.push({ segs: [dim("hiring and configuring coworkers: on the desktop office for now")] })
      return { title: "YOU", rows, keys: "j/k move · enter switch workspace · n new ticket · esc back" }
    }
  }
}

// ── drawing ────────────────────────────────────────────────────────────────────────────────────
function layoutScreen() {
  const cols = process.stdout.columns ?? 80, rowsN = process.stdout.rows ?? 40
  // as wide as the terminal, at the biggest whole scale (2 at least) that both fits its height and
  // leaves the room wide enough for its zones
  let next: number | null = null
  if (kitty && cell) {
    for (let k = Math.min(5, Math.floor(((rowsN - DETAIL - 3) * cell.h) / WIDE_H)); k >= 2 && next === null; k--) {
      const w = Math.floor((cols * cell.w) / k)
      if (w >= WIDE_MIN_W) next = w
    }
  }
  if (next !== wide) { wide = next; rooms.clear() }
  g = { ...(wide ? geometry(wide, WIDE_H, cols, rowsN, DETAIL + 3, cell, kitty) : geometry(W, H, cols, rowsN, DETAIL + 3, cell, kitty)), row: 1 }
  frame = null; sentImage = false
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
}

function draw() {
  if (!g) return
  const cols = process.stdout.columns ?? 80, termRows = process.stdout.rows ?? 40
  const a = view()
  let o = `${ESC}[?2026h`
  // header: the workspace, and what waits elsewhere
  const elsewhere = all.threads.filter((t) => t.workspace_id !== ws && needsYou(t)).length
  o += `${ESC}[1;1H` + line([{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(), fg: ROLE.body, bold: true }, key(" › "),
    ...(all.ok ? [] : [{ s: `  ${all.note ?? "channel down"}`, fg: ROLE.alarm }]), ...(elsewhere ? [pink(`  ! ${elsewhere} elsewhere`)] : [])], cols)
  // the room
  const room0 = room()
  const fresh = !frame
  if (fresh || roomChanged) { frame = room0.render(a, { picked, armed: null, person: mode.kind === "person" ? mode.name : null }, measureFor(g)); roomChanged = false }
  if (g.kitty && (!sentImage || fresh || imageDirty)) { o += kittyImage(frame!, g); sentImage = true; imageDirty = false }
  if (!g.kitty) textLayer(frame!, g).forEach((l, i) => { o += `${ESC}[${g.row + 1 + i};${g.col + 1}H${l}` })
  // the tip line: what the pointer is over, or what just happened
  const tipRow = g.row + g.rows + 1
  o += `${ESC}[${tipRow};1H` + line([tip ? dim(` ${tip.split("\n").join(" · ")}`) : status ? key(` ${status}`) : dim("")], cols)
  // the detail pane, fixed height
  const d = detail()
  rows = d.rows
  const top = tipRow + 1, body = Math.max(1, termRows - top - 1)
  o += `${ESC}[${top};1H` + line([{ s: ` ${d.title} `, fg: ROLE.ground, bg: ROLE.key }, dim(" " + "─".repeat(Math.max(0, cols - d.title.length - 3)))], cols)
  const selectable = rows.some((r) => r.open)
  if (sel >= rows.length) sel = Math.max(0, rows.length - 1)
  const first = Math.max(0, Math.min(sel - Math.floor((body - 1) / 2), rows.length - (body - 1)))
  for (let i = 0; i < body - 1; i++) {
    const r = rows[first + i]
    const mark = r && selectable && first + i === sel && mode.kind !== "thread" && mode.kind !== "person" ? key("▸ ") : plain("  ")
    o += `${ESC}[${top + 1 + i};1H` + line(r ? [mark, ...r.segs] : [], cols)
  }
  // the footer: the keys that work here, or the line you are typing, or a confirm
  o += `${ESC}[${termRows};1H` + line(input ? [pink(` ${input.label}: `), plain(input.text), { s: "█", fg: ROLE.prose }] : confirm ? [pink(` ${confirm.label} (y/n)`)] : [dim(` ${d.keys}`)], cols)
  out(o + `${ESC}[?2026l`)
}
// ── input ──────────────────────────────────────────────────────────────────────────────────────
function onKey(k: string) {
  if (input) {
    if (k === "esc") input = null
    else if (k === "enter") { const i = input; input = null; i.submit(i.text) }
    else if (k === "backspace") input.text = [...input.text].slice(0, -1).join("")
    else if ([...k].length === 1 && k >= " ") input.text += k
    return draw()
  }
  if (confirm) { const c = confirm; confirm = null; if (k === "y") c.run(); return draw() }
  const tid = openThread()
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
    case "enter": return mode.kind === "ticket" ? rows[3]?.open?.() : rows[sel]?.open?.()
    case "c": return open({ kind: "crew" })
    case "t": return open({ kind: "column", col: 0 })
    case "o": return open({ kind: "notes" })
    case "a": return open({ kind: "calendar" })
    case "n": return newTicket()
    case "p": room().pet(); return
    case "s": if (mode.kind === "ticket") rows[2]?.open?.(); return
    case "r": if (tid !== null) reply(tid); return
    case "x": if (tid !== null) { confirm = { label: `close #${tid} as done`, run: () => did(data.closeThread(tid)) }; draw() } return
  }
  if (/^[1-9]$/.test(k) && tid !== null) {
    const opt = threadOf(tid)?.prompt?.options?.[Number(k) - 1]
    if (opt) did(data.post(tid, opt.key))
  }
}

function onMouse(m: Extract<Input, { t: "mouse" }>) {
  if (!frame || !g) return
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

function quit() { leave(); process.exit(0) }

// ── startup ────────────────────────────────────────────────────────────────────────────────────
async function main() {
  if (!process.stdin.isTTY) { console.error("office: needs a terminal"); process.exit(1) }
  enter()
  process.on("uncaughtException", (e) => { leave(); console.error(e); process.exit(1) })
  let pending = "", detected = false
  const ready = new Promise<void>((res) => {
    process.stdin.on("data", (b: Buffer) => {
      const { inputs, rest } = tokenize(pending + b.toString("utf8"))
      pending = rest
      for (const i of inputs) {
        if (i.t === "cell") cell = { w: i.w, h: i.h }
        else if (i.t === "graphics") kitty = process.env.OFFICE_GRAPHICS !== "blocks" && i.ok
        else if (i.t === "da") { if (!detected) { detected = true; res() } }
        else if (!detected) continue
        else if (i.t === "key") onKey(i.key)
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
  process.stdout.on("resize", () => { query(); setTimeout(() => { layoutScreen(); draw() }, 150) })
  await refresh()
  setInterval(refresh, 10_000)
  // the room's clock: 10 Hz, drawn only when it changed
  setInterval(() => { if (room().step(view())) { roomChanged = true; imageDirty = true; draw() } }, 100)
}
main()
