// The hiring hall's candidate: everything on the card is a pure function of (seed, taken) and the stored edits.
// roll() does no I/O and calls no model; hall.json (below) stores only seed + edits, and a drawn soul/pitch
// is laid over the skeleton by the caller.
import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { hash, lookOf, rollLook, type Look } from "./sprites"
import { SLOTS, type PartSpec, type Slot } from "./parts"
import { SOUL_SECTIONS } from "./souls"

export type Vocab = { archetypes: string[]; grades: string[]; specialties: string[] }
export type Field = "name" | "archetype" | "grade" | "specialty"
export type Locks = { slots?: Slot[]; fields?: Field[] }
export type Candidate = {
  seed: string; name: string; archetype: string; grade: string; specialty: string
  look: Look; pitch: string; soul: string; drawn: boolean
}

// no "uqbar": the operator's delegate, an outside citizen — a seat by that name would take its identity
// Characters from across Borges' stories, so the hall doesn't cycle a handful once the bench has
// taken the famous ones. Never the names the machine itself uses (funes, menard, aleph, orbis, tlon,
// uqbar, borges): those are systems and citizens, not coworkers.
export const BORGES = [
  // Death and the Compass · Emma Zunz · The Garden of Forking Paths
  "lonnrot", "scharlach", "treviranus", "yarmolinsky", "azevedo", "ginzberg", "gryphius", "emma", "zunz",
  "loewenthal", "tsun", "albert", "stephen", "madden",
  // The Secret Miracle · The Form of the Sword · Theme of the Traitor and the Hero · The Immortal
  "hladik", "jaromir", "moon", "kilpatrick", "nolan", "ryan", "cartaphilus", "rufus", "argos",
  // Funes · The Aleph · Deutsches Requiem · The Zahir · Averroes' Search · The Writing of the God
  "ireneo", "beatriz", "carlos", "daneri", "zunino", "zungri", "linde", "jerusalem", "teodelina", "zahir",
  "averroes", "farach", "albucasim", "tzinacan", "asterion",
  // Tlön (its people, not its name) · Three Versions of Judas · Pierre Menard's reader · Herbert Quain
  "ashe", "erfjord", "haslam", "runeberg", "nils", "pierre", "quain", "herbert", "tertius",
  // The Dead Man · The South · The Other Death · The Gospel According to Mark · The Intruder
  "otalora", "bandeira", "ulpiano", "dahlmann", "damian", "espinosa", "gutre", "nilsen", "juliana",
  "cristian", "eduardo",
  // The Duel · Ulrikke · The Congress · Guayaquil · The End · The Encounter · Juan Muraña · Rosendo
  "glencairn", "clara", "marta", "ulrikke", "otarola", "ferri", "glencoe", "zimerman", "recabarren",
  "uriarte", "duncan", "murana", "rosendo",
  // Ibn Hakkan al-Bokhari · Shakespeare's Memory · The Rose of Paracelsus · Blue Tigers · the rest
  "dunraven", "unwin", "zaid", "abenjacan", "soergel", "thorpe", "paracelsus", "griesebach", "craigie",
  "almotasim", "hakim", "droctulft", "cruz", "fervor", "jauregui", "villari", "castro", "eastman",
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

/** a way of making names: the parts its syllables are built from */
type Parts = { onsets: readonly string[]; vowels: readonly string[]; codas: readonly string[] }
// everyday: names a person could have (Tesi, Biwon, Rupar); no x endings, no vowel pileups
const EVERYDAY: Parts = {
  onsets: ["b", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "br", "st", "sh", "ch", "j", "w"],
  vowels: ["a", "e", "i", "o", "u", "a", "e", "i", "o"],
  codas: ["", "", "", "", "n", "r", "l", "s", "m"],
}
// villain: hard clusters and dark endings (Laekrix, Rustox, Vorthaz)
const VILLAIN: Parts = {
  onsets: ["k", "kr", "dr", "gr", "th", "v", "z", "x", "s", "sk", "m", "r", "vr", "zh", "n", "g"],
  vowels: ["a", "o", "u", "e", "i", "ae", "au", "y"],
  codas: ["x", "th", "z", "r", "k", "n", "rax", "oth", "", ""],
}
/** a name that can be said aloud, seeded, from `parts`: two or three syllables, the last perhaps closed */
const spoken = (seed: string, parts: Parts) => {
  const n = 2 + (hash(`${seed}len`) % 2)
  // a name may open on a vowel (Ana, Oren); a syllable inside one never does, or vowels pile up
  const onset = (i: number) => (i === 0 && hash(`${seed}open`) % 6 === 0 ? "" : parts.onsets[hash(`${seed}o${i}`) % parts.onsets.length]!)
  const syllables = Array.from({ length: n }, (_, i) => onset(i) + parts.vowels[hash(`${seed}v${i}`) % parts.vowels.length]!)
  return syllables.join("") + parts.codas[hash(`${seed}c`) % parts.codas.length]!
}
/** which generator a candidate's name comes from, by its seed, out of five: three everyday, one villain, one Borges */
const styleOf = (seed: string): "everyday" | "villain" | "borges" => (["everyday", "everyday", "everyday", "villain", "borges"] as const)[hash(seed + "style") % 5]!

export function roll(seed: string, o: { taken: readonly string[]; vocab: Vocab }): Candidate {
  const pick = <T,>(xs: readonly T[], k: string) => xs[hash(seed + k) % xs.length]!
  const free = BORGES.filter(n => !o.taken.includes(n))
  // mostly a name of its own, everyday or villainous; now and then a Borges character, as a flavour
  const style = styleOf(seed)
  const name = style === "borges" && free.length ? pick(free, "name") : freshName(seed, o.taken, style === "villain" ? VILLAIN : EVERYDAY)
  const look: Look = { ...lookOf(seed), ...rollLook(seed) }
  const archetype = pick(o.vocab.archetypes, "archetype")
  const grade = pick(o.vocab.grades, "grade")
  const specialty = pick(o.vocab.specialties, "specialty")

  const pitch = pick(PITCHES, "pitch")(name, grade, archetype, specialty)
  const soul = SOUL_SECTIONS.filter(h => h !== "Diary").map(h => `## ${h}\n`).join("\n")
  return { seed, name, archetype, grade, specialty, look, pitch, soul, drawn: false }
}

/** what a hand or a pass stores about a candidate: the seed plus edits, never the rendered result */
export type Overrides = Partial<Pick<Candidate, "name" | "archetype" | "grade" | "specialty" | "soul" | "pitch" | "drawn">> & {
  /** a slot's edited part; null clears the slot */
  parts?: Partial<Record<Slot, PartSpec | null>>
}
export type PileEntry = { seed: string; overrides: Overrides }
export type Hall = { seed: string; locks: Locks; overrides: Overrides; pile: PileEntry[] }

export const PILE_MAX = 50
const EDITABLE = ["name", "archetype", "grade", "specialty", "soul", "pitch", "drawn"] as const

export const emptyHall = (): Hall => ({ seed: "hall:1", locks: {}, overrides: {}, pile: [] })

const FIELDS: readonly Field[] = ["name", "archetype", "grade", "specialty"]

function cleanLocks(raw: unknown): Locks {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>
  const keep = <T extends string>(xs: unknown, legal: readonly T[]) => (Array.isArray(xs) ? legal.filter(l => xs.includes(l)) : [])
  const slots = keep(r.slots, SLOTS), fields = keep(r.fields, FIELDS)
  return { ...(slots.length ? { slots } : {}), ...(fields.length ? { fields } : {}) }
}

// Server.Soul's name check: the name becomes souls/<name>.md and a looks.json key
export const SOUL_NAME = /^[a-z0-9][a-z0-9_-]*$/
function cleanOverrides(raw: unknown): Overrides {
  if (!raw || typeof raw !== "object") return {}
  const { name, ...rest } = raw as Overrides
  return typeof name === "string" && SOUL_NAME.test(name) ? { ...rest, name } : rest
}

export function loadHall(path: string): Hall {
  try {
    const j = JSON.parse(readFileSync(path, "utf8"))
    return {
      seed: typeof j.seed === "string" ? j.seed : "hall:1",
      locks: cleanLocks(j.locks),
      overrides: cleanOverrides(j.overrides),
      pile: Array.isArray(j.pile) ? j.pile.filter((e: PileEntry) => e && typeof e.seed === "string").map((e: PileEntry) => ({ seed: e.seed, overrides: cleanOverrides(e.overrides) })) : [],
    }
  } catch { return emptyHall() }
}

export function saveHall(path: string, h: Hall): void {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(h, null, 2) + "\n")
}

/** mtime and size of the file; "" when absent, so a poll can tell an edit from a quiet file */
export function hallSignature(path: string): string {
  try { const s = statSync(path); return `${s.mtimeMs}:${s.size}` } catch { return "" }
}

export function applyOverrides(c: Candidate, ov: Overrides): Candidate {
  const out: Candidate = { ...c }
  for (const k of EDITABLE) if (ov[k] !== undefined) (out as Record<string, unknown>)[k] = ov[k]
  if (ov.parts) {
    const parts = { ...c.look.parts }
    for (const s of SLOTS) {
      const p = ov.parts[s]
      if (p === null) delete parts[s]
      else if (p) parts[s] = p
    }
    out.look = { ...c.look, parts }
  }
  return out
}

export const pushPile = (pile: PileEntry[], e: PileEntry): PileEntry[] => [...pile.filter(p => p.seed !== e.seed), e].slice(-PILE_MAX)
export const dropPile = (pile: PileEntry[], i: number): PileEntry[] => pile.filter((_, j) => j !== i)

type Ctx = { taken: readonly string[]; vocab: Vocab }

/** the card the hall shows: the seed rolled, then the edits laid over it */
export const candidateOf = (h: Hall, o: Ctx): Candidate => applyOverrides(roll(h.seed, o), h.overrides)

/**
 * Draw the next seed. What a lock keeps is written into the new overrides, so the stored hall (seed +
 * overrides) re-renders the same card after a restart without remembering the previous one.
 */
export function pass(h: Hall, o: Ctx): Hall {
  const cur = candidateOf(h, o), overrides: Overrides = {}
  const o2 = overrides as Record<string, unknown>
  // a taken name is used up: the lock stays, the next seed rolls a fresh one
  for (const f of h.locks.fields ?? []) if (!(f === "name" && o.taken.includes(cur.name))) o2[f] = cur[f]
  const slots = h.locks.slots ?? []
  if (slots.length) overrides.parts = Object.fromEntries(slots.map(s => [s, cur.look.parts?.[s] ?? null]))
  return { ...h, seed: nextSeed(h.seed), overrides }
}

/** put the current card on the pile, then pass; the shown name is baked in so the entry re-renders as it was seen */
export const maybe = (h: Hall, o: Ctx): Hall => {
  const name = candidateOf(h, o).name
  return pass({ ...h, pile: pushPile(h.pile, { seed: h.seed, overrides: { ...h.overrides, name } }) }, o)
}

export function bringBack(h: Hall, i: number): Hall {
  const e = h.pile[i]
  return e ? { ...h, seed: e.seed, overrides: e.overrides, pile: dropPile(h.pile, i) } : h
}

/**
 * every name already seated, any crew, any workspace: the snapshot's bench is the crew on shift, so a
 * name off shift (a night crew's) read as free and its hire hit the seat's unique key
 */
export const seatedNames = (a: { bench: { name: string }[]; shifts?: { name: string }[] }): string[] =>
  [...new Set([...(a.shifts ?? []).map((s) => s.name), ...a.bench.map((b) => b.name)])]

/** names a new candidate must not take: the bench's and everyone on the pile */
export const takenNames = (h: Hall, bench: readonly string[], vocab: Vocab): string[] => [
  ...bench,
  ...h.pile.map(e => e.overrides.name ?? roll(e.seed, { taken: bench, vocab }).name),
]

export function toggleLock(l: Locks, kind: "slots" | "fields", key: Slot | Field): Locks {
  const cur = (l[kind] ?? []) as string[]
  const next = cur.includes(key) ? cur.filter(k => k !== key) : [...cur, key]
  const { [kind]: _, ...rest } = l
  return next.length ? { ...rest, [kind]: next } : rest
}

/** a spoken name no seat or pile entry has, nor a Borges one: the seed's, re-rolled on a clash */
function freshName(seed: string, taken: readonly string[], parts: Parts): string {
  for (let i = 0; ; i++) {
    const n = spoken(`${seed}n${i}`, parts)
    if (n.length >= 4 && n.length <= 10 && !taken.includes(n) && !(BORGES as readonly string[]).includes(n)) return n
  }
}
