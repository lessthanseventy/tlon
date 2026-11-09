import { viewOf, type BoardCtx } from "../kit/crew"
import { resolvePets } from "../kit/pets"
import { ROLE } from "../kit/palette"
import { seatedNames, takenNames, type Vocab } from "../kit/hall"
import { storeNamesTaken } from "../kit/store"
import { shirtOf } from "../kit/sprites"
import { operatorOf } from "../kit/types"
import { loadPets } from "./pets"
import { type Seg } from "./term"
import { next } from "./order"
import { DETAIL, cardKey, dim } from "./ui"
import type { State } from "./state"

export const waiting = (app: State, what: string): Seg => { const why = app.readWhys.get(cardKey(app.mode)); return dim(why ? `couldn't read: ${why}` : what) }

/** the workspace's crews by name, as its seats are on them; `all` is every crew, no crew of its own */
export const crewsOf = (app: State, w: number | null) => [...new Set((app.all.shifts ?? []).filter((x) => x.workspace_id === w && x.crew !== "all").map((x) => x.crew))].sort()

export const GRADES = ["junior", "senior", "greybeard"], SPECIALTIES = ["office", "server"]

export const hallVocab = (app: State): Vocab => {
  const names = app.all.archetypes.filter((a) => !a.meta).map((a) => a.name)
  return { archetypes: names.length ? names : ["builder"], grades: GRADES, specialties: SPECIALTIES }
}

export const hallCtx = (app: State) => ({ taken: takenNames(app.hall, seatedNames(app.all), hallVocab(app)), vocab: hallVocab(app) })

export const storeTaken = (app: State) => storeNamesTaken(app.all.bench.map((b) => b.name), app.petsNow ?? resolvePets(loadPets()), app.store.species)

export const cardBox = (app: State) => (!app.reader && app.mode.kind === "thread" && app.cardReply?.tid === app.mode.tid ? app.cardReply : null)

export const view = (app: State) => {
  if (app.viewed?.all !== app.all || app.viewed.ws !== app.ws) app.viewed = { all: app.all, ws: app.ws, v: viewOf(app.all, app.ws) }
  return app.viewed.v
}

export const crewOn = (app: State) => app.all.workspaces.find((w) => w.id === app.ws)?.shift ?? ""

/** the crew after the one on, in name order; null with fewer than two crews */
export const nextCrew = (app: State) => { const cs = crewsOf(app, app.ws); return cs.length > 1 ? next(cs, crewOn(app)) : null }

export const checkLine = /^#(\d+) (?:verify|landing)/

/** the workline the machine's full check runs on now ("#235 verify …"), or null for a session's own check */
export const checkingId = (app: State): number | null => { const m = checkLine.exec(app.all.health?.checks?.running ?? ""); return m ? Number(m[1]) : null }

/** the worklines whose check waits in the queue */
export const checkWaitingIds = (app: State): number[] => (app.all.health?.checks?.waiting ?? []).flatMap((l) => { const m = checkLine.exec(l); return m ? [Number(m[1])] : [] })

/** what the board reads beyond the snapshot: the leaf cap, and which threads are on the needs list */
export const boardCtx = (app: State): BoardCtx => {
  const cap = app.settings?.knobs.find((k) => k.key === "max_leaves")?.value
  return { maxLeaves: typeof cap === "number" ? cap : null, needs: app.needs.flatMap((n) => (n.thread_id ? [n.thread_id] : [])), checking: checkingId(app), checkWaiting: checkWaitingIds(app), merging: app.all.health?.merge_queue ?? [] }
}

export const threadOf = (app: State, id: number | null) => (id === null ? undefined : app.all.threads.find((t) => t.id === id))

/** the model a seat gets when it sets none of its own: its archetype's, else the server's default */
export const inheritedModel = (app: State, archetype: string | null) => app.all.archetypes.find((x) => x.name === archetype)?.model || "the server's default"

export const wsName = (app: State, id = app.ws) => app.all.workspaces.find((w) => w.id === id)?.name ?? "—"

export const changed = (app: State) => { app.roomChanged = true; app.imageDirty = true }

/** an author's colour: you in pink, the server dim, a coworker in their archetype's */
export const authorColor = (app: State, author: string) =>
  author === operatorOf(app.all) ? ROLE.attention : author === "tlon" ? ROLE.inactive : shirtOf(app.all.bench.find((b) => b.name === author)?.archetype)

/** the detail pane's lines under its title, with a one-line foot */
export const paneRows = (app: State) => (app.g ? Math.max(1, (process.stdout.rows ?? 40) - (app.g.row + app.g.rows + 2) - 2) : DETAIL - 2)
