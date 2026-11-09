import type { Frame } from "../kit/canvas"
import { marginInk } from "../kit/margin"
import { renderHome } from "../kit/homeart"
import { mailbox } from "../kit/mailbox"
import { phoneBar, ringFrame } from "../kit/surfaces"
import { ROLE } from "../kit/palette"
import { bedScene, lifeHeader, streakFrames } from "../kit/life"
import { usageHeader } from "../kit/usage"
import { operatorOf } from "../kit/types"
import { H, W } from "../rooms/rail"
import { BAND, OFF_DOOR, OFF_W, WIDE_H, WIDE_MIN_W, WideRoom } from "../rooms/wide"
import * as data from "./data"
import { adder, hints } from "./keys"
import { PLAY } from "./sandbox"
import { rank } from "./fuzzy"
import { loadFloor } from "./home"
import { geometry, kittyImage, measureFor, textLayer } from "./paint"
import { footLines, follow as followSel, offset, type Hint, type Window } from "./pane"
import { badge, cells, ESC, line, out, type Seg } from "./term"
import { centerViewport, clipFrame, type Viewport } from "./viewport"
import { downHeader } from "./down"
import { type Row, type Prompt } from "./state"
import { detail } from "./cards/index"
import { boardCtx, cardBox, checkingId, crewOn, crewsOf, nextCrew, threadOf, view, wsName } from "./select"
import { ACTIONS_W, DETAIL, cols, dim, key, keyName, pink, plain } from "./ui"
import { threadActions } from "./cards/thread"
import type { Screen } from "./ctl"
import type { State } from "./state"

/** a click on the header's crew: the next crew goes on */
export const toggleShift = (app: State, ctl: Screen) => {
  const to = nextCrew(app)
  if (app.ws !== null && to) void ctl.did(data.shiftSwitch(app.ws, to))
}

/** the crew on, once the workspace has crews; nothing for one with none */
export const shiftHeader = (app: State) => (crewsOf(app, app.ws).length ? `⇄ ${crewOn(app)} crew` : null)

/** the header's queues: what is checked and what is merged right now */
export function queuesHeader(app: State): string | null {
  const c = app.all.health?.checks, mq = app.all.health?.merge_queue ?? []
  const landing = mq.find((m) => m.state === "landing"), queued = mq.filter((m) => m.state === "queued").length
  const parts = [
    c?.running ? (checkingId(app) ? `✓ checking #${checkingId(app)}` : "✓ a full check runs") : null,
    c?.waiting.length ? `+${c.waiting.length} waiting` : null,
    landing ? `⤵ landing #${landing.thread_id}` : null,
    queued ? `${queued} queued to land` : null,
  ].filter(Boolean)
  return parts.length ? parts.join(" · ") : null
}

export const unread = (app: State) => app.feed.filter((x) => x.at > app.trayRead && x.who !== operatorOf(app.all)).length

/** main's office has moved past the revision this TUI started on */
export const updated = (app: State) => !!app.officeRev && !!app.all.revs?.office && app.all.revs.office !== app.officeRev

export function layoutScreen(app: State, ctl: Screen) {
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
  app.g = { ...(app.wide ? geometry(app.wide, (r0 => (r0 instanceof WideRoom ? r0.height : WIDE_H))(ctl.room()), colsN, rowsN, DETAIL + 3, app.cell, app.kitty, WIDE_H) : geometry(W, H, colsN, rowsN, DETAIL + 3, app.cell, app.kitty)), row: 1 }
  const vw = Math.min(app.g.floorW, (app.g.cols * app.g.cw) / app.g.k), vh = Math.min(app.g.floorH, (app.g.rows * app.g.ch) / app.g.k)
  app.viewport = app.follow
    ? centerViewport({ x: 0, y: 0, w: vw, h: vh }, OFF_W / 2, (BAND + OFF_DOOR) / 2, app.g.floorW, app.g.floorH)
    : centerViewport({ ...app.viewport, w: vw, h: vh }, app.viewport.x + app.viewport.w / 2, app.viewport.y + app.viewport.h / 2, app.g.floorW, app.g.floorH)
  app.frame = null; app.sentImage = false
  out(`${ESC}_Ga=d,d=A,q=2${ESC}\\${ESC}[2J`)
}

/** `roomOnly`: the room's clock moved and nothing else did — repaint the room and its tip, leave the header and the pane as the last full draw made them */
export function draw(app: State, ctl: Screen) { paint(app, ctl, false) }

export function paint(app: State, ctl: Screen, roomOnly: boolean) {
  if (!app.g || app.zoom) return
  const colsN = cols(), termRows = process.stdout.rows ?? 40
  if (app.reader) {
    app.paneCursor = null
    if (app.picker || app.confirm) { out(`${ESC}[?25l` + drawOverlay(app, ctl, colsN, termRows)); return }
    out(app.reader.draw(colsN, termRows, threadOf(app, app.reader.tid), [...threadActions(app, ctl, app.reader.tid, true).map((x) => `${x.key} ${x.label}`), "pgup/pgdn scroll", "esc back", "ctrl+] room"].join(" · ")))
    return
  }
  const a = view(app)
  const partial = roomOnly && app.paneCursor !== null
  let o = `${ESC}[?2026h${ESC}[?25l`
  // header: the workspace, and what waits elsewhere
  if (!partial) {
    const phone = phoneBar(app.bySurface.counts), usage = usageHeader(app.all, Date.now())
    const head: (Seg & { go?: () => void })[] = [{ s: " OFFICE ", fg: ROLE.ground, bg: ROLE.attention }, key(" ‹ "), { s: wsName(app), fg: ROLE.body, bold: true }, key(" › "),
      ...(app.all.ok ? [] : [{ s: `  ${downHeader(app.all, Date.now())}`, fg: ROLE.alarm }]),
      ...(phone ? badge({ s: `  ${ringFrame(Math.floor(Date.now() / 1000), phone.ringing)} ${phone.text} `, fg: ROLE.ground, bg: ROLE.attention, bold: true, go: ctl.inbox }) : []),
      ...(shiftHeader(app) ? [{ s: `  ${shiftHeader(app)}`, fg: ROLE.body, go: () => toggleShift(app, ctl) }] : []),
      ...(app.all.pause === "pencils_down" || app.all.pause === "lights_out" ? badge({ s: app.all.pause === "lights_out" ? "  ◼ lights out " : "  ✎ pencils down ", fg: ROLE.ground, bg: ROLE.attention, bold: true, go: () => ctl.ask2("back to work", () => void ctl.did(data.pause("back_to_work"))) }) : []),
      ...(queuesHeader(app) ? [{ s: `  ${queuesHeader(app)}`, fg: ROLE.live, go: () => ctl.open({ kind: "health" }) }] : []),
      ...(lifeHeader(app.all, app.ws) ? [{ s: `  ${lifeHeader(app.all, app.ws)}`, fg: ROLE.body }, dim("  (L)")] : []),
      ...(usage ? [{ s: `  ${usage.text}`, fg: usage.hot ? ROLE.attention : ROLE.body, bold: usage.hot }] : []),
      ...(updated(app) ? [{ s: "  office updated · R reloads", fg: ROLE.live, bold: true }] : []),
      ...(app.all.health?.state === "warn" ? [{ s: `  ⚠ ${app.all.health.problems[0]}`, fg: ROLE.alarm, go: () => ctl.open({ kind: "health" }) }] : []),
      ...(process.env.OFFICE_DEBUG ? [dim(`  viewport ${Math.round(app.viewport.x)},${Math.round(app.viewport.y)}`)] : [])]
    app.headHits = []
    let hx = 1
    for (const s of head) { const w = cells(s.s); if (s.go) app.headHits.push({ from: hx, to: hx + w - 1, go: s.go }); hx += w }
    o += `${ESC}[1;1H` + line(head, colsN)
  }
  // the room
  const room0 = ctl.room()
  const building = app.mode.kind === "build" && app.build !== null
  const fresh = !app.frame
  // leaving build mode puts the room back, however the mode was left
  if (!building && app.homeShown) {
    app.roomChanged = true; app.imageDirty = true
    app.homeNow = loadFloor()
    for (const r of app.rooms.values()) if (r instanceof WideRoom) { r.setHome(app.homeNow); r.setStreaks(streakFrames(app.lifeCard?.streaks ?? {})) }
    // the home below the office grows or shrinks with the home, and the room's rows with it
    layoutScreen(app, ctl)
  }
  app.homeShown = building
  const vp = building ? { x: 0, y: 0, w: app.viewport.w, h: app.viewport.h } : app.viewport
  if (building) {
    app.frame = renderHome({ top: app.build!.top, home: app.build!.home, cursor: app.build!.cursor, carrying: app.build!.carrying, refused: app.build!.refused, w: Math.ceil(vp.w), h: Math.ceil(vp.h), weather: a.weather?.kind, mail: mailbox(app.needs), frames: streakFrames(app.lifeCard?.streaks ?? {}), bed: bedScene(app.lifeCard?.today ?? [], Date.now()) })
    app.imageDirty = true
  } else if (fresh || app.roomChanged) { app.frame = room0.render(a, { picked: app.lit ?? app.picked, person: app.mode.kind === "person" ? app.mode.name : null, tray: unread(app), board: boardCtx(app), machine: app.bySurface.counts.machine, clipboard: app.bySurface.clipboard.filter((n) => n.workspace_id == null || n.workspace_id === app.ws) }, measureFor(app.g), app.world?.now()); app.roomChanged = false }
  const seen = clipFrame(app.frame!, vp)
  if (!building) addMargin(app, seen, vp)
  if (app.g.kitty && (!app.sentImage || fresh || app.imageDirty || app.panned)) { o += kittyImage(seen, app.g, vp); app.sentImage = true; app.imageDirty = false }
  if (!app.g.kitty) textLayer(seen, app.g, vp).forEach((l, i) => { o += `${ESC}[${app.g.row + 1 + i};${app.g.col + 1}H${l}` })
  app.panned = false
  // the tip line: what the pointer is over, or what just happened
  const tipRow = app.g.row + app.g.rows + 1
  o += `${ESC}[${tipRow};1H` + line([app.tip ? dim(` ${app.tip.split("\n").join(" · ")}`) : app.status ? key(` ${app.status}`) : dim("")], colsN)
  if (partial) return out(o + app.paneCursor + `${ESC}[?2026l`)
  const pane = drawPane(app, ctl, tipRow + 1, colsN, termRows)
  app.paneCursor = /\x1b\[\d+;\d+H\x1b\[\?25h$/.exec(pane)?.[0] ?? ""
  out(o + pane + `${ESC}[?2026l`)
}

/** the actions take j/k and enter when the card's rows have nothing to open */
export const actionsFocused = (app: State) => !app.rows.some((r) => r.open)

/** the keys that work everywhere a card's own actions don't claim them */
export const GLOBALS: Hint[] = hints("global")

/** a window's line `i`, as a row index, an "↑ N more" (-1) or "↓ N more" (-2), or nothing */
export function lineOf(w: Window, i: number): number | undefined {
  if (w.above && i === 0) return -1
  const j = i - (w.above ? 1 : 0)
  if (j < w.count) return w.first + j
  if (w.below && j === w.count) return -2
  return undefined
}

export const more = (w: Window, at: number, how: string): Seg[] => [dim(at === -1 ? `  ↑ ${w.above} more${how}` : `  ↓ ${w.below} more${how}`)]

export const fit = (s: string, w: number) => (cells(s) <= w ? s : `${[...s].slice(0, Math.max(0, w - 1)).join("")}…`)

/** the pane from row `top` to the foot: the finder, a multi-line input, or the card — its rows on the left, its actions on the right */
export function drawPane(app: State, ctl: Screen, top: number, colsN: number, termRows: number): string {
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
    const d = detail(app, ctl)
    const add = adder(`card:${app.mode.kind}`)
    title = d.title; app.acts = d.actions; tint = d.tint ?? ROLE.key
    segRows = d.rows.length ? d.rows : [{ segs: [dim(`nothing here yet${add ? ` — ${keyName(add.key)} ${add.label}` : ""}`)] }]
  }
  app.rows = segRows
  const split = app.acts.length > 0 && colsN >= 80
  const leftW = split ? colsN - ACTIONS_W - 1 : colsN
  const box = app.picker || app.input ? null : cardBox(app), bv = box?.ed.view(leftW - 4, 4), boxH = bv ? bv.rows.length + 1 : 0
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

export const cyclesSegs = (i: Prompt): Seg[] => (i.cycles ?? []).flatMap((c, n) => [dim(`${c.name} `), n === i.focus && (i.cycles?.length ?? 0) > 1 ? { s: `‹${c.values[c.i]!.label}› `, fg: ROLE.ground, bg: ROLE.key } : key(`‹${c.values[c.i]!.label}› `)])

/** the finder or a confirm over the reader: drawn in the bottom rows, the conversation above */
export function drawOverlay(app: State, ctl: Screen, colsN: number, termRows: number): string {
  const top = Math.max(2, termRows - DETAIL - 1)
  let o = `${ESC}[?2026h`
  for (let r = top; r <= termRows; r++) o += `${ESC}[${r};1H` + line([], colsN)
  return o + drawPane(app, ctl, top, colsN, termRows) + `${ESC}[?2026l`
}

/** the status line for a scene asked for off the play card */
export const scene = (started: boolean, r: { eventsHere(): boolean }, said: string): string =>
  started ? said : r.eventsHere() ? "a scene is running, or that event is switched off (the wackiness dial)" : "events need the wide room (kitty graphics)"

/** the margin notes over a clipped frame: text ink after the clip so a pan can't push it off-screen, hits first so they win */
export function addMargin(app: State, fr: Frame, vp: Viewport) {
  app.looks.see(app.notes, app.focused)
  const m = marginInk(app.notes, app.looks, app.lit, vp, app.g ? measureFor(app.g) : undefined)
  fr.ink.push(...m.ink)
  fr.hits.unshift(...m.hits)
}
