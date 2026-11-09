import { readFileSync, realpathSync, statSync } from "node:fs"
import { dirname } from "node:path"
import { FLOOR } from "../kit/margin"
import { resolvePets } from "../kit/pets"
import { useSouls } from "../kit/souls"
import { paced } from "./pace"
import { watchDirs } from "./watch"
import { loadSouls, soulsSignature } from "./souls"
import { useLookOverrides, type LookOverride } from "../kit/looks"
import { ROLE, useRoles, type Role } from "../kit/palette"
import { hallSignature, loadHall } from "../kit/hall"
import { castSignature, loadCast } from "../kit/cast"
import { loadStore } from "../kit/store"
import { NOW_PLAYING_FORMAT, parseNowPlaying, type NowPlaying } from "../kit/stereo"
import { WideRoom } from "../rooms/wide"
import * as data from "./data"
import { loadPets, PETS_PATH } from "./pets"
import { enter, leave, mute, query, tokenize } from "./term"
import { execSelf, selfArgv } from "./exec"
import { PALETTE, LOOKS, SOULS, HALL, CAST, STORE, PLAY_SEEN, readState, writeState } from "./state"
import { changed, threadOf, view } from "./select"
import { cols } from "./ui"
import type { State } from "./state"
import type { Boot } from "./ctl"

/** a hand edit of hall.json shows up on the next poll; true when it did */
export function followHall(app: State): boolean {
  const seen = hallSignature(HALL)
  if (seen === app.hallSeen) return false
  app.hallSeen = seen; app.hall = loadHall(HALL)
  return true
}

export function followCast(app: State): boolean {
  const seen = castSignature(CAST)
  if (seen === app.castSeen) return false
  app.castSeen = seen; app.cast = loadCast(CAST)
  return true
}

/** a hand edit of store.json shows up on the next poll; true when it did */
export function followStore(app: State): boolean {
  const seen = hallSignature(STORE)
  if (seen === app.storeSeen) return false
  app.storeSeen = seen; app.store = loadStore(STORE)
  return true
}

/** take the machine's palette if it changed since last look; true when it did */
export function followPalette(app: State): boolean {
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
export function followLooks(app: State): boolean {
  try {
    const real = realpathSync(LOOKS), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === app.looksSeen) return false
    app.looksSeen = seen
    useLookOverrides(JSON.parse(readFileSync(real, "utf8")) as Record<string, LookOverride>)
    return true
  } catch { return false }
}

/** take the machine's souls dir if a file came, went or changed; true when it did */
export function followSouls(app: State): boolean {
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
export function followPets(app: State): boolean {
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

// every interval this process runs, so a relaunch can stop them all
export const timers: ReturnType<typeof setInterval>[] = []

export const closers: (() => void)[] = []

export const every = (fn: () => unknown, ms: number) => { timers.push(setInterval(fn, ms)) }

/** a timer that, with the terminal unfocused, runs once per `idleMs` instead of every `ms` */
export const everyFocused = (app: State, fn: () => unknown, ms: number, idleMs = 30_000) => every(paced(() => app.focused, idleMs, fn), ms)

/** start this TUI over on the new code: hand the terminal back and exec the same command in place */
export async function relaunch() {
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

export async function pollPlayer(app: State, ctl: Boot) {
  if (app.playerBusy || Date.now() < app.playerRetry || !(ctl.room() instanceof WideRoom)) return
  app.playerBusy = true
  let now: NowPlaying | null = null
  try {
    const p = Bun.spawn(["playerctl", "metadata", "--format", NOW_PLAYING_FORMAT], { stdout: "pipe", stderr: "ignore" })
    const out = await new Response(p.stdout).text()
    if ((await p.exited) === 0) now = parseNowPlaying(out)
  } catch { /* no playerctl */ }
  app.playerBusy = false
  if (!now) app.playerRetry = Date.now() + 30_000
  const rm = ctl.room()
  if (rm instanceof WideRoom) rm.setPlayer(now)
}

/** refresh a thread's close look; true when its activity feed moved */
export async function pollActivity(app: State, ctl: Boot, tid: number) {
  const was = app.threads.get(tid)?.activity?.at(-1)
  await ctl.loadThread(tid)
  const now = app.threads.get(tid)?.activity?.at(-1)
  return was?.at !== now?.at || was?.summary !== now?.summary
}

export async function boot(app: State, ctl: Boot) {
  if (!process.stdin.isTTY) { console.error("office: needs a terminal"); process.exit(1) }
  followPalette(app)
  followLooks(app)
  followSouls(app)
  followPets(app)
  enter()
  process.on("uncaughtException", (e) => { leave(); console.error(e); process.exit(1) })
  let pending = "", detected = false
  const ready = new Promise<void>((res) => {
    process.stdin.on("data", (b: Buffer) => {
      if (app.zoom) return ctl.zoomInput(b)
      const { inputs, rest } = tokenize(pending + b.toString("utf8"))
      pending = rest
      for (const i of inputs) {
        if (i.t === "cell") app.cell = { w: i.w, h: i.h }
        else if (i.t === "graphics") app.kitty = process.env.OFFICE_GRAPHICS !== "blocks" && i.ok
        else if (i.t === "da") { if (!detected) { detected = true; res() } }
        else if (!detected) continue
        else if (i.t === "key") ctl.onKey(i.key)
        else if (i.t === "paste") ctl.onPaste(i.text)
        else if (i.t === "focus") { app.focused = i.on; app.looks.focus(i.on); if (!i.on) ctl.stampLooked(); ctl.draw() }
        else if (i.t === "mouse") ctl.onMouse(i)
      }
    })
    setTimeout(() => { if (!detected) { detected = true; res() } }, 500)
  })
  query()
  await ready
  // tmux eats the graphics protocol unless told to pass it through; blocks there by default
  if (process.env.TMUX && process.env.OFFICE_GRAPHICS !== "kitty") app.kitty = false
  ctl.layoutScreen()
  process.stdout.on("resize", () => {
    if (app.zoom) { app.zoom.view.resize(cols(), Math.max(2, (process.stdout.rows ?? 24) - 1)); return ctl.drawZoom() }
    query(); setTimeout(() => { ctl.layoutScreen(); ctl.draw() }, 150)
  })
  await ctl.refresh()
  if (app.world && process.env.OFFICE_PLAY_INTRO === "1" && !readState(PLAY_SEEN)) { writeState(PLAY_SEEN, "1"); ctl.open({ kind: "play" }) }
  everyFocused(app, ctl.refresh, 10_000)
  everyFocused(app, () => pollPlayer(app, ctl), 2000)
  everyFocused(app, ctl.watchTrophies, 1000)
  let sec = 0
  every(() => { app.looks.tick(1); if (app.focused && ++sec % 5 === 0) ctl.stampLooked(); if (app.focused && !app.reader && !app.zoom && app.notes.some((n) => { const a = app.looks.alpha(n); return a < 1 && a > FLOOR })) ctl.draw() }, 1000)
  every(() => { if (app.focused && ((app.mode.kind === "pet" && app.petDraft) || app.mode.kind === "store")) { app.previewTick += 10; ctl.draw() } }, 1000)
  every(() => { if (app.focused && app.bySurface.counts.phone > 0) ctl.draw() }, 1000) // the phone rings: its glyph shakes once a second
  const followFiles = () => { if ([followPalette(app), followLooks(app), followSouls(app), followPets(app), followHall(app), followStore(app), followCast(app)].some(Boolean)) { app.frame = null; ctl.draw() } }
  const real = (p: string) => { try { return realpathSync(p) } catch { return p } }
  const files = [PALETTE, LOOKS, PETS_PATH, HALL, STORE, CAST]
  const watched = watchDirs([...files, ...files.map(real)].map((f) => dirname(f)).concat(SOULS), followFiles)
  closers.push(watched.close)
  if (!watched.ok) everyFocused(app, followFiles, 1000)
  // another surface (the desktop's alert) asks to show a thread: open it, once per request, ignoring
  // what was asked before this TUI started
  let seenFocus = (await data.focus())?.at ?? 0
  everyFocused(app, async () => {
    const f = await data.focus()
    if (!f || f.at <= seenFocus) return
    seenFocus = f.at
    if (app.zoom) ctl.leaveZoom()
    ctl.goThread(f.thread_id, threadOf(app, f.thread_id)?.workspace_id)
    ctl.openReader(f.thread_id, {}, false)
  }, 1000, 5000)
  // a card showing a running coworker keeps their activity current
  everyFocused(app, () => {
    const tid = ctl.openThread()
    if (tid !== null && !app.zoom && !app.reader && threadOf(app, tid)?.live && !app.talkView.has(tid)) void pollActivity(app, ctl, tid).then((moved) => { if (moved) ctl.draw() })
  }, 1000)
  // the room's clock: 10 Hz, drawn only when it changed. The room's time is counted in these ticks, so
  // it always steps; it is the repaint (a whole frame each) that costs a room nobody watches a core:
  // none while the terminal is unfocused (the return to focus draws), 2 Hz while the office is calm
  // (paused, or no coworker live)
  const animate = process.env.OFFICE_NO_ANIMATE !== "1" // tests boot the TUI with it off: no frame to wait on
  let beat = 0, frames = 0, stale = false
  const calm = () => app.all.pause === "pencils_down" || app.all.pause === "lights_out" || !app.all.threads.some((t) => t.live)
  every(() => {
    if (animate && !app.reader && ctl.room().step(view(app))) { changed(app); stale = true }
    // the header and the pane catch up once a second; the frames between repaint the room alone
    if (stale && app.focused && (++beat % 5 === 0 || !calm())) { stale = false; ctl.paint(++frames % 10 !== 0) }
  }, 100)
}
