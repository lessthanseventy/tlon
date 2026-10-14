import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { DEFAULT, parse, type State } from "./whimsy"

export const load = (path: string): State => {
  try {
    return parse(readFileSync(path, "utf8"))
  } catch {
    return DEFAULT
  }
}

/** a read-only home just doesn't remember */
export function save(path: string, s: State) {
  try {
    mkdirSync(dirname(path), { recursive: true })
    writeFileSync(path, JSON.stringify(s, null, 2) + "\n")
  } catch {}
}
