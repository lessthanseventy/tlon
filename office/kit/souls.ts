
/** the §1 headings of the souls design: steps 2-4 read these by name, so they are the contract */
export const SOUL_SECTIONS = ["Where they're from", "Wants", "Fears", "Quirks", "People", "The side project", "Diary"] as const

export type Soul = { sections: Record<string, string>; raw: string }

/** forgiving: unknown `## ` headings are kept, missing ones are empty, text with no headings is just `raw` */
export function parseSoul(raw: string): Soul {
  // null-prototype maps: a heading is any text, `constructor` and `__proto__` included
  const sections: Record<string, string> = Object.assign(Object.create(null), Object.fromEntries(SOUL_SECTIONS.map(h => [h, ""])))
  let head: string | null = null
  const body: Record<string, string[]> = Object.create(null)
  for (const line of raw.split(/\r?\n/)) {
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

/** a one-line note a card shows under a section's heading, if the section has one */
export const soulNote = (head: string): string | undefined =>
  head === "People" ? "read by verb: admires / needles / would cover for — reworded, it yields no affinity" : undefined

/** what a card shows: the known sections in design order then any extras, filled ones only; a file with no headings shows raw */
export function soulLines(s: Soul): { head: string; text: string }[] {
  const known = new Set<string>(SOUL_SECTIONS)
  const order = [...SOUL_SECTIONS.filter(h => h !== "Diary"), ...Object.keys(s.sections).filter(h => !known.has(h)), "Diary"]
  const lines = order.filter(h => s.sections[h]).map(h => ({ head: h, text: s.sections[h]! }))
  const raw = s.raw.trim()
  return lines.length || !raw ? lines : [{ head: "", text: raw }]
}
