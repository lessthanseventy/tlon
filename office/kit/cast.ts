// cast.json: the office's own record of what the cast editor sets on a seat that the server has no field for
// (grade, specialty), keyed by seat name like looks.json. TLON_CAST points elsewhere; the sandbox keeps its own.
import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { SOUL_NAME } from "./hall"

export type Traits = { grade?: string; specialty?: string }
export type Cast = Record<string, Traits>

export function loadCast(path: string): Cast {
  try {
    const j = JSON.parse(readFileSync(path, "utf8")) as Record<string, Record<string, unknown>>
    const out: Cast = {}
    for (const [name, t] of Object.entries(j)) {
      if (!SOUL_NAME.test(name) || !t || typeof t !== "object") continue
      const traits: Traits = {}
      if (typeof t.grade === "string") traits.grade = t.grade
      if (typeof t.specialty === "string") traits.specialty = t.specialty
      if (Object.keys(traits).length) out[name] = traits
    }
    return out
  } catch { return {} }
}

export function saveCast(path: string, c: Cast): void {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(c, null, 2) + "\n")
}

/** mtime and size; "" when absent, so a poll can tell an edit from a quiet file */
export function castSignature(path: string): string {
  try { const s = statSync(path); return `${s.mtimeMs}:${s.size}` } catch { return "" }
}

export const setTrait = (c: Cast, name: string, field: keyof Traits, value: string): Cast =>
  ({ ...c, [name]: { ...c[name], [field]: value } })
