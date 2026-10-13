// The hiring hall's candidate: everything on the card is a pure function of (seed, locks, taken, prev).
// No I/O and no model here — a drawn soul/pitch is stored over the skeleton by the caller.
import { hash, lookOf, rollLook, type Look } from "./sprites"
import { SLOTS, type Slot } from "./parts"
import { SOUL_SECTIONS } from "./souls"

export type Vocab = { archetypes: string[]; grades: string[]; specialties: string[] }
export type Field = "name" | "archetype" | "grade" | "specialty"
export type Locks = { slots?: Slot[]; fields?: Field[] }
export type Candidate = {
  seed: string; name: string; archetype: string; grade: string; specialty: string
  look: Look; pitch: string; soul: string; drawn: boolean
}

export const BORGES = [
  "funes", "lonnrot", "tzinacan", "ireneo", "hladik", "otalora", "emma", "nolan", "asterion", "pierre",
  "menard", "droctulft", "cruz", "fervor", "zahir", "aleph", "beatriz", "carlos", "nils", "ts-ai-ang",
  "yu-tsun", "albert", "stephen", "runeberg", "uqbar", "orbis", "tertius", "herbert", "ashe", "borges",
] as const

const PITCHES = [
  (n: string, g: string, a: string, s: string) => `${n}: a ${g} ${a} for ${s}.`,
  (n: string, g: string, a: string, s: string) => `${n} is a ${g} ${a}; ${s} is where they go quiet and good.`,
  (n: string, g: string, a: string, s: string) => `Hire ${n}. ${g[0]!.toUpperCase()}${g.slice(1)} ${a}, ${s} first.`,
]

export function nextSeed(s: string): string {
  const n = /^hall:(\d+)$/.exec(s)?.[1]
  return `hall:${(n ? Number(n) : 0) + 1}`
}

export function roll(seed: string, o: { taken: readonly string[]; locks: Locks; prev?: Candidate; vocab: Vocab }): Candidate {
  const pick = <T,>(xs: readonly T[], k: string) => xs[hash(seed + k) % xs.length]!
  const locked = (f: Field) => !!o.locks.fields?.includes(f) && !!o.prev
  const free = BORGES.filter(n => !o.taken.includes(n))
  const fresh = free.length ? pick(free, "name") : `hall-${(hash(seed + "n") % 9000) + 1000}`
  const name = locked("name") && !o.taken.includes(o.prev!.name) ? o.prev!.name : fresh

  const rolled = rollLook(seed)
  const parts = { ...rolled.parts }
  for (const s of SLOTS) {
    if (!o.locks.slots?.includes(s) || !o.prev) continue
    const p = o.prev.look.parts?.[s]
    if (p) parts[s] = p
    else delete parts[s]
  }
  const look: Look = { ...lookOf(seed), ...rolled, parts }

  const field = (f: Exclude<Field, "name">, xs: string[]) => (locked(f) ? o.prev![f] : pick(xs, f))
  const archetype = field("archetype", o.vocab.archetypes)
  const grade = field("grade", o.vocab.grades)
  const specialty = field("specialty", o.vocab.specialties)

  const pitch = pick(PITCHES, "pitch")(name, grade, archetype, specialty)
  const soul = SOUL_SECTIONS.filter(h => h !== "Diary").map(h => `## ${h}\n`).join("\n")
  return { seed, name, archetype, grade, specialty, look, pitch, soul, drawn: false }
}
