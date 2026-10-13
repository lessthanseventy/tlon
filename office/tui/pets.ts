// pets.json: yours, like looks.json. `TLON_PETS` to point elsewhere; the sandbox keeps its own under $TMPDIR/tlon-sandbox.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import type { PetsFile } from "../kit/pets"

export const inSandbox = (argv: readonly string[] = process.argv, env: Record<string, string | undefined> = process.env) =>
  argv.includes("--sandbox") || env.OFFICE_SANDBOX === "1"

export function petsPath(sandbox: boolean, env: Record<string, string | undefined> = process.env, home = homedir(), tmp = tmpdir()): string {
  if (env.TLON_PETS) return env.TLON_PETS
  return sandbox ? join(tmp, "tlon-sandbox/pets.json") : join(env.XDG_CONFIG_HOME ?? join(home, ".config"), "tlon/pets.json")
}

export const PETS_PATH = petsPath(inSandbox())
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
