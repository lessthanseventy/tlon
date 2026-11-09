import { existsSync, mkdirSync, readFileSync, unlinkSync, watchFile, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { ROLE } from "../kit/palette"
import { BLANK_SOUL } from "../kit/hall"
import * as data from "./data"
import { ESC, leave, line, out } from "./term"
import { rows as vtRows, TerminalView, type Target } from "./terminal"
import { STATE_DIR, SOULS } from "./state"
import { threadOf } from "./select"
import { cols, key, stamp } from "./ui"
import { GAMES } from "./cards/home"
import type { Screen } from "./ctl"
import { draw, layoutScreen } from "./draw"
import type { State } from "./state"

// The whole screen is one coworker's terminal: a bar on top, every key to the pane but Ctrl-],
// which goes to the room.
export const ROOM_KEY = 0x1d // Ctrl-]

export async function zoomInto(app: State, ctl: Screen, tid: number) {
  const target = await data.terminal(tid)
  if (!target) { app.status = `#${tid} has no live terminal`; if (app.reader) app.reader.status = app.status; return draw(app, ctl) }
  zoomOn(app, ctl, target, `#${tid} ${threadOf(app, tid)?.lead ?? target.window} · terminal`)
}

/**
 * lazygit in the thread's worktree, in a tmux session the office keeps (`-L tlon-office`, one per
 * thread), so it is where you left it next time; quitting lazygit closes the window and the zoom.
 */
// a drive names its own (scripts/office-drive.sh), so its panes and files never land in the operator's office
export const OWN_TMUX = process.env.TLON_OFFICE_TMUX || "tlon-office"

export const OWN_DIR = `${process.env.XDG_RUNTIME_DIR ?? "/tmp"}/${OWN_TMUX}`

export async function zoomGit(app: State, ctl: Screen, tid: number) {
  if (!Bun.which("lazygit")) { app.status = "lazygit is not installed"; return draw(app, ctl) }
  const path = await data.worktree(tid)
  if (!path) { app.status = `#${tid} has no repo to show`; return draw(app, ctl) }
  const session = `git-${tid}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "lazygit", "-c", path, "lazygit")
  zoomOn(app, ctl, { socket: OWN_TMUX, session, window: "lazygit" }, `#${tid} ${threadOf(app, tid)?.lead ?? ""} · git`)
}

/** a workline's docs, picked from a list */
export async function pickDoc(app: State, ctl: Screen, tid: number) {
  const names = await data.docs(tid)
  if (!names.length) { app.status = `#${tid} has no docs yet`; return draw(app, ctl) }
  ctl.find(`DOCS · #${tid}`, names.map((n) => ({ segs: [{ s: n, fg: ROLE.prose }], text: n, run: () => { app.picker = null; void readDoc(app, ctl, tid, n) } })))
}

/** a doc read in the office's own tmux: glow renders markdown, else bat, else less */
export async function readDoc(app: State, ctl: Screen, tid: number, name: string) {
  const text = await data.doc(tid, name)
  if (text === null) { app.status = `#${tid}: no ${name}`; return draw(app, ctl) }
  pageThrough(app, ctl, `doc-${tid}-${name.replace(/\W/g, "_")}`, text, `#${tid} · ${name}`)
}

export function pageThrough(app: State, ctl: Screen, session: string, text: string, label: string) {
  const dir = OWN_DIR, file = `${dir}/${session}`
  mkdirSync(dir, { recursive: true }); writeFileSync(file, text)
  const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  tmux("kill-session", "-t", `=${session}`)
  const show = `if command -v glow >/dev/null; then glow -p "$0"; elif command -v bat >/dev/null; then bat --paging=always --style=plain -l md "$0"; else less "$0"; fi`
  tmux("new-session", "-d", "-s", session, "-n", "doc", "sh", "-c", show, file)
  zoomOn(app, ctl, { socket: OWN_TMUX, session, window: "doc" }, label)
}

export async function readPage(app: State, ctl: Screen, id: number) {
  if (app.ws === null) return
  const p = await data.dumpPage(app.ws, id)
  if (!p) { app.status = "that page can't be read: the server isn't answering"; return draw(app, ctl) }
  pageThrough(app, ctl, `page-${app.ws}-${id}`, p.body, `the dump · ${stamp(p.at)}`)
}

/** an earlier page made the dump again; the page it replaces is kept, so this is undone the same way */
export async function restorePage(app: State, ctl: Screen, id: number) {
  if (app.ws === null) return
  const w = app.ws, p = await data.dumpPage(w, id)
  if (!p) { app.status = "that page can't be read: the server isn't answering"; return draw(app, ctl) }
  if (Bun.spawnSync(["tmux", "-L", OWN_TMUX, "has-session", "-t", `=dump-${w}`]).exitCode === 0) { app.status = "the dump is open in its editor: close it first, then put the page back"; return draw(app, ctl) }
  let file: string | null = null
  try { file = readFileSync(dumpFile(w), "utf8") } catch {}
  const now = await data.dump(w)
  if (!now) { app.status = "the dump can't be read: the server isn't answering"; return draw(app, ctl) }
  if (app.dumpSending.has(w) || (file?.trim() && file !== now.body)) { app.status = "the dump has a save still on its way: D to send it, then put the page back"; return draw(app, ctl) }
  await ctl.did(data.dumpPut(w, p.body).then((r) => {
    if (r.ok) { app.dumpSent.set(w, p.body); mkdirSync(dirname(dumpFile(w)), { recursive: true }); writeFileSync(dumpFile(w), p.body) }
    return r.line
  }))
  await ctl.loadCard(); draw(app, ctl)
}

// on disk, not the runtime tmpfs: words the server hasn't taken yet survive a logout or a reboot
export const dumpFile = (w: number) => join(STATE_DIR, OWN_TMUX, `dump-${w}.md`)

export function syncDump(app: State, ctl: Screen, w: number, quiet = false) {
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
    if (app.dumpAgain.delete(w)) syncDump(app, ctl, w)
    return r
  })
  // quiet runs from inside a refresh, so it must not start another (`did` does)
  if (quiet) void put.then((r) => { if (r.ok) { app.status = r.line; draw(app, ctl) } })
  else void ctl.did(put.then((r) => r.line)).then(ctl.loadCard).then(() => draw(app, ctl))
}

export async function openDump(app: State, ctl: Screen) {
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
  if (!app.dumpWatched.has(w)) { app.dumpWatched.add(w); watchFile(file, { interval: 1000 }, () => syncDump(app, ctl, w)) }
  if (!open) {
    let unsent: string | null = null
    try { unsent = readFileSync(file, "utf8") } catch {}
    if (unsent?.trim() && unsent !== app.dumpSent.get(w)) { app.status = "sending what you wrote while the server was away"; syncDump(app, ctl, w) }
    else { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, app.dumpSent.get(w)!) }
    tmux("new-session", "-d", "-s", session, "-n", "dump", ...EDITOR_ENV(), "sh", "-c", EDIT_SH, file)
  }
  zoomOn(app, ctl, { socket: OWN_TMUX, session, window: "dump" }, "the dump", () => syncDump(app, ctl, w))
}

// VISUAL/EDITOR is a shell command, as git reads it: flags work, and a path with spaces is quoted inside it
export const EDIT_SH = `e="\${VISUAL:-\${EDITOR:-}}"; [ -n "$e" ] || e="$(command -v nvim || command -v vi)"; [ -n "$e" ] || { echo "no editor: set VISUAL or EDITOR"; read _; exit 1; }; eval "exec $e \\"\\$0\\""`

// a tmux server already up keeps its own env, so the editor this TUI was started with is handed over
export const EDITOR_ENV = () => ["VISUAL", "EDITOR"].flatMap((k) => (process.env[k] ? ["-e", `${k}=${process.env[k]}`] : []))

/** a seat's soul in the operator's own editor, zoomed like the dump; the file starts blank when absent and is never overwritten */
export function openSoul(app: State, ctl: Screen, name: string) {
  const file = join(SOULS, `${name}.md`), session = `soul-${name}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  try { mkdirSync(SOULS, { recursive: true }); writeFileSync(file, BLANK_SOUL, { flag: "wx" }) } catch { /* theirs already: never overwritten */ }
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "soul", ...EDITOR_ENV(), "sh", "-c", EDIT_SH, file)
  zoomOn(app, ctl, { socket: OWN_TMUX, session, window: "soul" }, "the soul", () => { app.soulsSeen = "" })
}

/** a game in the office's own tmux, one session each, so a game you leave is where you left it */
export function play(app: State, ctl: Screen, g: (typeof GAMES)[number]) {
  const session = `arcade-${g.cmd}`, tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])
  if (tmux("has-session", "-t", `=${session}`).exitCode !== 0) tmux("new-session", "-d", "-s", session, "-n", "game", g.cmd)
  zoomOn(app, ctl, { socket: OWN_TMUX, session, window: "game" }, `arcade · ${g.name}`)
}

export function zoomOn(app: State, ctl: Screen, target: Target, label: string, after?: () => void) {
  const colsN = cols(), rowsN = Math.max(2, (process.stdout.rows ?? 24) - 1)
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[?1003l${ESC}[?1006l${ESC}[?2004l${ESC}[2J`)
  app.zoom = { label, after, view: new TerminalView(target, colsN, rowsN, () => drawZoom(app), () => leaveZoom(app, ctl)) }
  drawZoom(app)
}

export function drawZoom(app: State) {
  if (!app.zoom) return
  const colsN = cols(), vt = app.zoom.view.vt
  // no autowrap while drawing: a row the VT and this terminal measure differently can't wrap and scroll the bar away
  let o = `${ESC}[?2026h${ESC}[?7l${ESC}[?25l${ESC}[1;1H` + line([{ s: " ROOM ", fg: ROLE.ground, bg: ROLE.attention }, key(" ctrl+] room "), { s: app.zoom.label, fg: ROLE.body, bold: true }], colsN)
  vtRows(vt).forEach((r, i) => { o += `${ESC}[${i + 2};1H${r}` })
  const b = vt.buffer.active
  o += `${ESC}[?7h${ESC}[${b.cursorY + 2};${b.cursorX + 1}H${ESC}[?25h${ESC}[?2026l`
  out(o)
}

export function leaveZoom(app: State, ctl: Screen, toTheRoom = false): void {
  if (!app.zoom) return
  const z = app.zoom
  app.zoom = null
  z.view.close()
  out(`${ESC}[0m${ESC}[?25l${ESC}[?1003h${ESC}[?1006h${ESC}[?2004h`)
  z.after?.()
  if (toTheRoom) return toRoom(app, ctl)
  if (app.reader) { out(`${ESC}[2J`); return draw(app, ctl) }
  layoutScreen(app, ctl); draw(app, ctl)
}

/** raw keys while zoomed: Ctrl-] goes to the room, the rest goes to the pane as it came */
export function zoomInput(app: State, ctl: Screen, b: Uint8Array) {
  const at = b.indexOf(ROOM_KEY)
  if (at < 0) return app.zoom?.view.send(b)
  app.zoom?.view.send(b.subarray(0, at))
  leaveZoom(app, ctl, true)
}

/** Ctrl-] from anywhere: the room with nothing open over it */
export function toRoom(app: State, ctl: Screen): void {
  if (app.zoom) return leaveZoom(app, ctl, true)
  if (app.input && !app.input.ed.empty) app.banked.set(app.input.label, app.input.ed.text)
  ctl.bankReader()
  app.reader = null; app.input = null; ctl.back(true); app.roomChanged = true
  out(`${ESC}[?25l`); layoutScreen(app, ctl); draw(app, ctl)
}

export function quit(app: State) { app.zoom?.view.close(); leave(); process.exit(0) }
