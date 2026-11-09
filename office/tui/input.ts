import { isKonami, KONAMI } from "../kit/eggs"
import { findSecret } from "../kit/trophies"
import { COLS, crewOf } from "../kit/crew"
import { trimCustom } from "../kit/looks"
import { stepRow } from "./hall"
import { stepStoreRow } from "./store"
import { flagOn } from "../kit/types"
import { BAND, OFF_DOOR, OFF_W } from "../rooms/wide"
import * as data from "./data"
import { LEGEND_CHARS } from "./keys"
import { roomKey } from "./sandbox"
import { Editor } from "./editor"
import { rank } from "./fuzzy"
import { hitAt } from "./paint"
import { type Input } from "./term"
import { centerViewport, clipFrame, panViewport } from "./viewport"
import { TOY_KEYS } from "./state"
import { detail } from "./cards/index"
import { cardBox, changed, view } from "./select"
import { keyName } from "./ui"
import { threadActions } from "./cards/thread"
import { relaunch } from "./boot"
import type { Screen } from "./ctl"
import { actionsFocused, addMargin, draw, updated } from "./draw"
import type { State } from "./state"

export function stepWs(app: State, ctl: Screen, d: 1 | -1) {
  const list = app.all.workspaces
  if (!list.length) return
  const i = list.findIndex((w) => w.id === app.ws)
  ctl.goWs(list[(i + d + list.length) % list.length]!.id)
}

/** a key while a thread card's reply box has focus: Enter sends, Esc leaves the box (the card stays) */
export function boxKey(app: State, ctl: Screen, box: NonNullable<typeof app.cardReply>, k: string) {
  if (k === "esc") { box.focused = false; return draw(app, ctl) }
  if (k === "enter") {
    if (box.ed.empty) return
    const body = box.ed.text
    box.ed = new Editor(); app.scroll = Infinity
    const sent = data.post(box.tid, body)
    // a post that did not go puts the words back in the box, ahead of anything typed since
    void sent.then((line) => { if (!data.landed(line)) box.ed = new Editor(box.ed.empty ? body : `${body}\n${box.ed.text}`) })
    void ctl.did(sent)
    return draw(app, ctl)
  }
  if (k === "pgup" || k === "pgdn") return page(app, ctl, k === "pgdn" ? 1 : -1)
  box.ed.key(k)
  draw(app, ctl)
}

export function inputKey(app: State, ctl: Screen, k: string) {
  const i = app.input!
  if (k === "esc") { app.input = null; return draw(app, ctl) }
  if (k === "enter") { app.input = null; i.submit(i.ed.text, (i.cycles ?? []).map((c) => c.values[c.i]!.value)); return draw(app, ctl) }
  if ((k === "tab" || k === "backtab") && i.cycles?.length) {
    if (k === "backtab") i.focus = (i.focus + 1) % i.cycles.length
    else { const c = i.cycles[i.focus]!; c.i = (c.i + 1) % c.values.length }
    return draw(app, ctl)
  }
  i.ed.key(k)
  draw(app, ctl)
}

export function pickerKey(app: State, ctl: Screen, k: string) {
  const p = app.picker!
  const shown = rank(p.q.text, p.items, (x) => x.text)
  if (k === "esc") { app.picker = null; return draw(app, ctl) }
  if (k === "enter") { const it = shown[p.sel]; app.picker = null; it?.run(); return draw(app, ctl) }
  if (k === "down" || k === "ctrl-n" || k === "tab") { p.sel = Math.min(p.sel + 1, shown.length - 1); return draw(app, ctl) }
  if (k === "up" || k === "ctrl-p" || k === "backtab") { p.sel = Math.max(p.sel - 1, 0); return draw(app, ctl) }
  if (p.q.key(k)) p.sel = 0
  draw(app, ctl)
}

export function paintAt(app: State, ctl: Screen, ch: string) {
  if (app.mode.kind !== "look-editor" || !app.editBuf) return
  const view = app.mode.view, row = app.editBuf[view]![app.editCursor.y]!.split("")
  row[app.editCursor.x] = ch
  if (app.editMirror) row[11 - app.editCursor.x] = ch
  app.editBuf[view]![app.editCursor.y] = row.join("")
  draw(app, ctl)
}

export function editorKey(app: State, ctl: Screen, k: string) {
  if (app.mode.kind !== "look-editor" || !app.editBuf) return
  const { name, view } = app.mode
  if (k === "up") { app.editCursor.y = Math.max(0, app.editCursor.y - 1); return draw(app, ctl) }
  if (k === "down") { app.editCursor.y = Math.min(21, app.editCursor.y + 1); return draw(app, ctl) }
  if (k === "left") { app.editCursor.x = Math.max(0, app.editCursor.x - 1); return draw(app, ctl) }
  if (k === "right") { app.editCursor.x = Math.min(11, app.editCursor.x + 1); return draw(app, ctl) }
  if (k === "m") { app.editMirror = !app.editMirror; return draw(app, ctl) }
  if (k === "1" || k === "2" || k === "3") {
    app.mode = { kind: "look-editor", name, view: k === "1" ? "front" : k === "2" ? "side" : "back", from: app.mode.from, hall: app.mode.hall }
    return draw(app, ctl)
  }
  if (k === "esc") {
    if (app.editEntry) app.editBuf[view] = [...app.editEntry[view]]
    app.mode = { kind: "look", name, from: app.mode.from, hall: app.mode.hall }; app.sel = 0; app.snapSel = true; return draw(app, ctl)
  }
  if (k === "enter") {
    if (app.lookDraft) {
      const custom = trimCustom(app.editBuf)
      if (custom) app.lookDraft.custom = custom
      else delete app.lookDraft.custom
    }
    app.mode = { kind: "look", name, from: app.mode.from, hall: app.mode.hall }; app.sel = 0; app.snapSel = true; return draw(app, ctl)
  }
  if (k === ".") return paintAt(app, ctl, ".")
  if ((LEGEND_CHARS as readonly string[]).includes(k)) return paintAt(app, ctl, k)
}

/** the help card over the card you are on: its keys, the globals, the reader's and, in the sandbox, the play keys */
export function help(app: State, ctl: Screen) {
  if (app.mode.kind === "help") return
  const d = detail(app, ctl)
  ctl.open({ kind: "help", from: app.mode, title: d.title, keys: d.actions.map((x) => ({ key: keyName(x.key), label: x.label })) })
}

/** one key, one thing to do with the toy; true when the key was one of them. Off the sandbox only the room's keys, with OFFICE_TOY_KEYS=1 */
export function toyKey(app: State, ctl: Screen, k: string): boolean {
  if (!app.world && !roomKey(k, detail(app, ctl).actions.some((x) => x.key === k), TOY_KEYS)) return false
  switch (k) {
    case "E": ctl.open({ kind: "play" }); draw(app, ctl); return true
    default: return false
  }
}

export function onKey(app: State, ctl: Screen, k: string) {
  app.keyLog = [...app.keyLog, k].slice(-KONAMI.length)
  if (isKonami(app.keyLog)) { app.keyLog = []; ctl.record(findSecret(app.trophies, "konami")); ctl.room().disco(); app.status = "↑↑↓↓←→←→BA — everybody dance"; changed(app); return draw(app, ctl) }
  if (k === ROOM_CTRL) return ctl.toRoom()
  if (app.picker) return pickerKey(app, ctl, k)
  if (app.input) return inputKey(app, ctl, k)
  if (app.confirm) {
    const c = app.confirm; app.confirm = null
    if (k === "y" || k === "enter") c.run()
    else { app.status = "cancelled"; if (app.reader) app.reader.status = app.status }
    return draw(app, ctl)
  }
  if (app.mode.kind === "look-editor") return editorKey(app, ctl, k)
  if (app.mode.kind === "hall" && (k === "tab" || k === "backtab")) { app.snapSel = false; app.sel = stepRow(app.sel, k === "tab" ? 1 : -1); return draw(app, ctl) }
  if (app.mode.kind === "store" && (k === "tab" || k === "backtab")) { app.snapSel = false; app.sel = stepStoreRow(app.sel, k === "tab" ? 1 : -1); return draw(app, ctl) }
  if (app.reader) {
    const r = app.reader.key(k, Math.max(1, (process.stdout.rows ?? 24) - 6))
    if (r === "leave") return ctl.closeReader()
    if (r === "pass") return threadActions(app, ctl, app.reader.tid, true).find((x) => x.key === k)?.run()
    if (r !== "done") void r.then(() => draw(app, ctl))
    return draw(app, ctl)
  }
  const box = cardBox(app)
  if (box?.focused) return boxKey(app, ctl, box, k)
  // a live thread's own ⏎ steps into the session; on any other thread card ⏎ is back into the box
  if (box && k === "enter" && !detail(app, ctl).actions.some((x) => x.key === "enter")) { box.focused = true; return draw(app, ctl) }
  if (toyKey(app, ctl, k)) return
  // the card's own actions first: a key there means what its actions pane says
  const name = k === " " ? "space" : k
  const own = detail(app, ctl).actions.find((x) => x.key === name)
  if (own) return own.run()
  const onActions = actionsFocused(app)
  switch (k) {
    case "q": case "ctrl-c": return ctl.quit()
    case "esc": ctl.back(); app.roomChanged = true; return draw(app, ctl)
    case "[": return stepWs(app, ctl, -1)
    case "]": return stepWs(app, ctl, 1)
    case "tab": case "backtab": {
      const crew = crewOf(view(app))
      if (!crew.length) return
      const i = app.mode.kind === "person" ? crew.findIndex((c) => c.name === (app.mode as { name: string }).name) : -1
      return ctl.open({ kind: "person", name: crew[(i + (k === "tab" ? 1 : -1) + crew.length) % crew.length]!.name })
    }
    case "j": case "down":
      app.snapSel = false
      if (onActions) app.asel = Math.min(app.asel + 1, app.acts.length - 1); else app.sel = Math.min(app.sel + 1, app.rows.length - 1)
      return draw(app, ctl)
    case "k": case "up":
      app.snapSel = false
      if (onActions) app.asel = Math.max(app.asel - 1, 0); else app.sel = Math.max(app.sel - 1, 0)
      return draw(app, ctl)
    case "left": if (app.mode.kind === "column") return ctl.open({ kind: "column", col: (app.mode.col + COLS.length - 1) % COLS.length }); return
    case "shift-up": case "shift-down": case "shift-left": case "shift-right": {
      const dx = app.g.cw / app.g.k, dy = app.g.ch / app.g.k
      const [ddx, ddy] = k === "shift-left" ? [-dx, 0] : k === "shift-right" ? [dx, 0] : k === "shift-up" ? [0, -dy] : [0, dy]
      app.viewport = panViewport(app.viewport, ddx, ddy, app.g.floorW, app.g.floorH); app.follow = false; app.panned = true
      return draw(app, ctl)
    }
    case ".":
      app.viewport = centerViewport(app.viewport, OFF_W / 2, (BAND + OFF_DOOR) / 2, app.g.floorW, app.g.floorH); app.follow = true; app.panned = true
      return draw(app, ctl)
    case ",": {
      const need = app.needs[0]
      const seat = need ? app.all.roster.find((r) => r.thread_id === need.thread_id) : null
      const at = seat ? ctl.room().at(seat.agent) : null
      if (!at) return
      app.viewport = centerViewport(app.viewport, at.x, at.y, app.g.floorW, app.g.floorH); app.panned = true
      return draw(app, ctl)
    }
    case "pgdn": case "pgup": return page(app, ctl, k === "pgdn" ? 1 : -1)
    case "enter":
      if (app.mode.kind === "home" && app.lit !== null && !app.reader) return ctl.act({ kind: "thread", tid: app.lit })
      return onActions ? app.acts[app.asel]?.run() : app.rows[app.sel]?.open?.()
    case "/": case "ctrl-k": return void ctl.finder()
    case "?": return help(app, ctl)
    case "i": return ctl.inbox()
    case "R": if (updated(app)) void relaunch(); return
    case "'": return ctl.talk(null)
    case "n": return ctl.newThread()
    case "I": return ctl.newTicket()
    case "c": return ctl.open({ kind: "crew" })
    case "t": return ctl.open({ kind: "column", col: 0 })
    case "o": return ctl.open({ kind: "notes" })
    case "f": return ctl.open({ kind: "archive" })
    case "a": return ctl.open({ kind: "calendar" })
    case "w": return ctl.open({ kind: "tray" })
    case "!": return ctl.open({ kind: "triage" })
    case "H": return ctl.open({ kind: "health" })
    case "b": return ctl.open({ kind: "memory" })
    case "L": if (app.all.life?.[String(app.ws)]) ctl.open({ kind: "life" }); return
    case "B": if (flagOn(app.all, "build_mode")) ctl.open({ kind: "build" }); return
    case "U": return ctl.open({ kind: "entry" })
    case "O": return ctl.open({ kind: "boss" })
    case "S": return ctl.open({ kind: "settings" })
    case "p": ctl.room().pet(); changed(app); return draw(app, ctl)
  }
}

/** a page of the card's rows, by the selection when they open, else by the view */
export function page(app: State, ctl: Screen, dir: 1 | -1, by = Math.max(1, app.pane.room - 2)) {
  app.snapSel = false
  if (actionsFocused(app)) app.scroll = Math.max(0, (Number.isFinite(app.scroll) ? app.scroll : app.pane.first) + dir * by)
  else app.sel = Math.max(0, Math.min(app.sel + dir * by, app.rows.length - 1))
  draw(app, ctl)
}

export function onPaste(app: State, ctl: Screen, text: string) {
  if (app.picker) { app.picker.q.insert(text); return draw(app, ctl) }
  if (app.input) { app.input.ed.insert(text); return draw(app, ctl) }
  if (app.reader) { app.reader.paste(text); return draw(app, ctl) }
  const box = cardBox(app)
  if (box) { box.ed.insert(text); box.focused = true; return draw(app, ctl) }
}

export function onMouse(app: State, ctl: Screen, m: Extract<Input, { t: "mouse" }>) {
  if (!app.frame || !app.g || app.reader) return
  const inRoom0 = m.row - 1 >= app.g.row && m.row - 1 < app.g.row + app.g.rows
  if (m.motion && m.button === 0) {
    if (inRoom0 && app.drag) {
      const dx = (app.drag.col - m.col) * (app.g.cw / app.g.k), dy = (app.drag.row - m.row) * (app.g.ch / app.g.k)
      app.viewport = panViewport(app.viewport, dx, dy, app.g.floorW, app.g.floorH); app.follow = false; app.panned = true
      app.drag = { col: m.col, row: m.row }
      return draw(app, ctl)
    }
    if (inRoom0) app.drag = { col: m.col, row: m.row }
    return
  }
  app.drag = null
  // the wheel over the pane scrolls it
  if (m.press && (m.button === 64 || m.button === 65) && m.row > app.pane.top) return page(app, ctl, m.button === 65 ? 1 : -1, 3)
  const clipped = clipFrame(app.frame, app.viewport)
  addMargin(app, clipped, app.viewport)
  const h = hitAt(clipped, app.g, m.col, m.row, app.viewport)
  if (m.motion) {
    const t = h?.tip ?? "", over = h?.note ?? null
    if (over !== app.lit) { app.lit = over; app.tip = t; app.roomChanged = true; return draw(app, ctl) }
    if (t !== app.tip) { app.tip = t; draw(app, ctl) }
    return
  }
  if (!m.press || m.button !== 0) return
  if (m.row === 1) return app.headHits.find((x) => m.col >= x.from && m.col <= x.to)?.go()
  const inRoom = inRoom0
  if (h) return ctl.act(h.act)
  // a click on bare floor clears the slate, as on the desktop
  if (inRoom) { ctl.back(true); app.roomChanged = true; return draw(app, ctl) }
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

/** Ctrl-] as `tokenize` names it: a control character is ctrl- and its byte + 0x60 */
export const ROOM_CTRL = "ctrl-}"
