// home.json: yours, like palette.json. `TLON_HOME` to point elsewhere.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import type { Home } from "../kit/home"

export const HOME_PATH = process.env.TLON_HOME
  ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/home.json")

export function loadHome(path: string = HOME_PATH): Home {
  try {
    const j = JSON.parse(readFileSync(path, "utf8"))
    if (Array.isArray(j?.tiles)) return { tiles: j.tiles }
  } catch { /* no file, or not JSON: an empty home */ }
  return { tiles: [] }
}

export function saveHome(home: Home, path: string = HOME_PATH): void {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, `${JSON.stringify(home, null, 2)}\n`)
}
