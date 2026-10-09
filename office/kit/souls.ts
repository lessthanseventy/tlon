import { readdirSync, readFileSync, statSync } from "node:fs"
import { join } from "node:path"

/** the §1 headings of the souls design: steps 2-4 read these by name, so they are the contract */
export const SOUL_SECTIONS = ["Where they're from", "Wants", "Fears", "Quirks", "People", "The side project", "Diary"] as const

export type Soul = { sections: Record<string, string>; raw: string }

/** forgiving: unknown `## ` headings are kept, missing ones are empty, text with no headings is just `raw` */
export function parseSoul(raw: string): Soul {
  const sections: Record<string, string> = Object.fromEntries(SOUL_SECTIONS.map(h => [h, ""]))
  let head: string | null = null
  const body: Record<string, string[]> = {}
  for (const line of raw.split("\n")) {
    const m = /^##\s+(.+?)\s*$/.exec(line)
    if (m) { head = m[1]!; body[head] ??= []; continue }
    if (head) body[head]!.push(line)
  }
  for (const [h, lines] of Object.entries(body)) sections[h] = lines.join("\n").trim()
  return { sections, raw }
}

let souls: Record<string, Soul> = {}
let gen = 0

/** take the machine's souls dir if it changed — same shape as looks.ts */
export function useSouls(s: Record<string, Soul>) { souls = s; gen++ }
export function soulFor(name: string): Soul | undefined { return souls[name] }
/** bumps on every useSouls call */
export function soulsGen(): number { return gen }

const files = (dir: string) => { try { return readdirSync(dir).filter(f => f.endsWith(".md")).sort() } catch { return [] } }

/** names and mtimes of the dir's `<name>.md` files; "" when there are none, so a poll can tell a change from a quiet dir */
export function soulsSignature(dir: string): string {
  return files(dir).map(f => { try { return `${f}@${statSync(join(dir, f)).mtimeMs}` } catch { return f } }).join("|")
}

export function loadSouls(dir: string): Record<string, Soul> {
  const out: Record<string, Soul> = {}
  for (const f of files(dir)) {
    try { out[f.slice(0, -3)] = parseSoul(readFileSync(join(dir, f), "utf8")) } catch { /* unreadable: no soul, not a crash */ }
  }
  return out
}

/** what a card shows: the known sections in design order then any extras, filled ones only; a file with no headings shows raw */
export function soulLines(s: Soul): { head: string; text: string }[] {
  const known = new Set<string>(SOUL_SECTIONS)
  const order = [...SOUL_SECTIONS.filter(h => h !== "Diary"), ...Object.keys(s.sections).filter(h => !known.has(h)), "Diary"]
  const lines = order.filter(h => s.sections[h]).map(h => ({ head: h, text: s.sections[h]! }))
  const raw = s.raw.trim()
  return lines.length || !raw ? lines : [{ head: "", text: raw }]
}
