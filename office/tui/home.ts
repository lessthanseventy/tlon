// home.json: yours, like palette.json. `TLON_HOME` to point elsewhere.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { CATALOGUE, type Build, type Home, type HomeTile } from "../kit/home"

export const HOME_PATH = process.env.TLON_HOME
  ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/home.json")

const isTile = (t: unknown): t is HomeTile =>
  typeof t === "object" && t !== null
  && CATALOGUE.includes((t as { kind?: unknown }).kind as HomeTile["kind"])
  && Array.isArray((t as { at?: unknown }).at)
  && (t as { at: unknown[] }).at.length === 2
  && (t as { at: unknown[] }).at.every((n) => typeof n === "number")

export function loadHome(path: string = HOME_PATH): Home {
  try {
    const j = JSON.parse(readFileSync(path, "utf8"))
    if (Array.isArray(j?.tiles)) return { tiles: j.tiles.filter(isTile) }
  } catch { /* no file, or not JSON: an empty home */ }
  return { tiles: [] }
}

export function saveHome(home: Home, path: string = HOME_PATH): void {
  try {
    mkdirSync(dirname(path), { recursive: true })
    writeFileSync(path, `${JSON.stringify(home, null, 2)}\n`)
  } catch { /* a read-only or blocked home: it just won't remember */ }
}

/** one build-mode step: applies `f`, and saves the home only when the step wrote (a move, a pick-up or a refused drop does not) */
export function applyBuild(b: Build, f: (b: Build) => Build, save: (h: Home) => void = saveHome): Build {
  const next = f(b)
  if (next.writes !== b.writes) save(next.home)
  return next
}
