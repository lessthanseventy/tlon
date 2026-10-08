// pets.json: yours, like looks.json. `TLON_PETS` to point elsewhere.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import type { PetsFile } from "../kit/pets"

export const PETS_PATH = process.env.TLON_PETS
  ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/pets.json")

export function loadPets(path: string = PETS_PATH): PetsFile | undefined {
  try {
    const j = JSON.parse(readFileSync(path, "utf8"))
    return j && typeof j === "object" && !Array.isArray(j) ? j : undefined
  } catch { return undefined }
}

/** read-merge-write: a slot's fields merge, so a save writes only what changed */
export function savePets(file: PetsFile, path: string = PETS_PATH): void {
  const now = loadPets(path) ?? {}
  const next: PetsFile = { ...now, ...file }
  for (const slot of ["cat", "dog"] as const) if (file[slot]) next[slot] = { ...now[slot], ...file[slot] }
  try {
    mkdirSync(dirname(path), { recursive: true })
    writeFileSync(path, `${JSON.stringify(next, null, 2)}\n`)
  } catch { /* a read-only home: it just won't remember */ }
}
