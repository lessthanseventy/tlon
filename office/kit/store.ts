// The pet store's candidate: a pure function of (species, seed, taken); store.json keeps only the species, seed, locks and
// edits, never the rendered card. roll() does no I/O and calls no model. kit/hall.ts is the same shape for people.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { SHADES, SLOT_SPECIES, SPECIES, slotOf, type PetsFile, type Species } from "./pets"
import { hash } from "./sprites"
import { clampAxis, type Temperament } from "./temperament"

export const NAMES = ["Biscuit", "Pumpkin", "Mochi", "Pebble", "Juniper", "Clementine", "Otto", "Waffles", "Sprout", "Nutmeg", "Pixel", "Marble", "Tofu", "Maple", "Sesame", "Basil"] as const
export type StoreRow = "name" | "warmth" | "wits" | "energy" | "shade"
export const STORE_ROWS: readonly StoreRow[] = ["name", "warmth", "wits", "energy", "shade"]
export type Candidate = { seed: string; species: Species; name: string; temperament: Temperament; shade: number }
export type Overrides = { name?: string; shade?: number; temperament?: Partial<Temperament> }
export type Store = { species: Species; seed: string; locks: StoreRow[]; overrides: Overrides }

/** what the store offers: every species, each adopting into the slot its family belongs to (slotOf) */
export const SHELF: readonly Species[] = SPECIES
const LABEL: Record<string, string> = { rock: "pet rock", baoaqu: "A Bao A Qu" }
export const labelOf = (sp: string) => LABEL[sp] ?? sp

export const emptyStore = (): Store => ({ species: "cat", seed: "store:1", locks: [], overrides: {} })
const seedN = (seed: string) => Number(/^store:(\d+)$/.exec(seed)?.[1] ?? 0)

export function roll(species: Species, seed: string, taken: readonly string[]): Candidate {
  const h = (k: string) => hash(`${species}:${seed}:${k}`)
  const free = NAMES.filter((n) => !taken.includes(n))
  const name = free.length ? free[h("name") % free.length]! : `pet-${(h("n") % 9000) + 1000}`
  const axis = (k: string) => clampAxis((h(k) % 5) - 2)
  return { seed, species, name, temperament: { warmth: axis("warmth"), wits: axis("wits"), energy: axis("energy") }, shade: h("shade") % SHADES }
}

/** `taken` is the card's own species' list: a carried lock or a typed name that is taken there gives way to the roll */
export function candidateOf(s: Store, taken: readonly string[]): Candidate {
  const c = roll(s.species, s.seed, taken), o = s.overrides
  return { ...c, name: o.name && !taken.includes(o.name) ? o.name : c.name, shade: o.shade ?? c.shade, temperament: { ...c.temperament, ...o.temperament } }
}

/** what a lock keeps goes into the next overrides, so the stored store re-renders the same card after a restart */
function carry(s: Store, taken: readonly string[]): Overrides {
  const c = candidateOf(s, taken), o: Overrides = {}
  for (const r of s.locks) {
    if (r === "name") { if (!taken.includes(c.name)) o.name = c.name }
    else if (r === "shade") o.shade = c.shade
    else o.temperament = { ...o.temperament, [r]: c.temperament[r] }
  }
  return o
}

export const pass = (s: Store, taken: readonly string[]): Store => ({ ...s, seed: `store:${seedN(s.seed) + 1}`, overrides: carry(s, taken) })
export const back = (s: Store, taken: readonly string[]): Store => ({ ...s, seed: `store:${Math.max(1, seedN(s.seed) - 1)}`, overrides: carry(s, taken) })
export function shelve(s: Store, step: 1 | -1, taken: readonly string[]): Store {
  const i = SHELF.indexOf(s.species), species = SHELF[(i + step + SHELF.length) % SHELF.length]!
  return { ...s, species, overrides: carry(s, taken) }
}
export const toggleLock = (s: Store, r: StoreRow): Store => ({ ...s, locks: s.locks.includes(r) ? s.locks.filter((x) => x !== r) : [...s.locks, r] })
export const rename = (s: Store, name: string): Store => ({ ...s, overrides: { ...s.overrides, name } })

/** names a new pet must not take: the bench's and the other slot's pet (the occupant it replaces leaves) */
export function storeNamesTaken(bench: readonly string[], pets: { cat: { name: string }; dog: { name: string } }, species: string): string[] {
  const other = (slotOf(species) ?? "cat") === "cat" ? "dog" : "cat"
  return [...bench, pets[other].name]
}

/** the pets.json fragment that adopts `c` into `slot` (replacing its occupant), or null: not that slot's species, or no name */
export function adopt(c: Candidate, slot: "cat" | "dog"): PetsFile | null {
  if (!(SLOT_SPECIES[slot] as readonly string[]).includes(c.species) || !c.name.trim()) return null
  return { [slot]: { name: c.name.trim(), species: c.species, temperament: { ...c.temperament }, shade: c.shade } }
}

function cleanOverrides(raw: unknown): Overrides {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>, o: Overrides = {}
  if (typeof r.name === "string" && r.name.trim()) o.name = r.name.trim()
  if (Number.isInteger(r.shade) && (r.shade as number) >= 0 && (r.shade as number) < SHADES) o.shade = r.shade as number
  if (r.temperament && typeof r.temperament === "object") {
    const t = r.temperament as Record<string, unknown>, out: Partial<Temperament> = {}
    for (const a of ["warmth", "wits", "energy"] as const) if (a in t) out[a] = clampAxis(Number(t[a]) || 0)
    if (Object.keys(out).length) o.temperament = out
  }
  return o
}

export function loadStore(path: string): Store {
  try {
    const j = JSON.parse(readFileSync(path, "utf8")), d = emptyStore()
    return {
      species: SHELF.includes(j.species) ? j.species : d.species,
      seed: typeof j.seed === "string" && /^store:\d+$/.test(j.seed) ? j.seed : d.seed,
      locks: Array.isArray(j.locks) ? STORE_ROWS.filter((r) => j.locks.includes(r)) : [],
      overrides: cleanOverrides(j.overrides),
    }
  } catch { return emptyStore() }
}

export function saveStore(path: string, s: Store): void {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(s, null, 2) + "\n")
}
