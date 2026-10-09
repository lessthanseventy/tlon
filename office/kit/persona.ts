/** a seat's persona as the server stores it (`Server.Persona`); `source` says who wrote it, `edited` that a person changed it after */
export type Persona = {
  seed: number
  source: "model" | "fallback"
  voice: string
  backstory: string
  quirks: { desk_object: string; hobby: string; catchphrase: string; pet_peeve: string }
  edited?: boolean
}

/** the persona's card lines, each at most `width` wide; nothing for a seat without one */
export function personaLines(p: Persona | null | undefined, width: number): string[] {
  if (!p) return []
  const out: string[] = []
  let line = ""
  for (const w of p.backstory.split(/\s+/).filter(Boolean)) {
    if (line && line.length + 1 + w.length > width) { out.push(line); line = w } else line = line ? `${line} ${w}` : w
  }
  if (line) out.push(line)
  out.push(`voice: ${p.voice}`, `desk: ${p.quirks.desk_object}`, `hobby: ${p.quirks.hobby}`, `says: "${p.quirks.catchphrase}"`, `peeve: ${p.quirks.pet_peeve}`)
  out.push(p.edited ? `edited · seed ${p.seed}` : p.source === "fallback" ? `handwritten · seed ${p.seed}` : `seed ${p.seed}`)
  return out
}
