// The cast editor's rows as data (the god view): one row per seat, one cell per field. Pure, so it needs no
// terminal to test; main.ts draws it and wires each cell's key to the existing editor for that field.
import { roll, type Vocab } from "../kit/hall"
import type { Cast } from "../kit/cast"

export const CAST_FIELDS = ["name", "archetype", "look", "soul", "voice", "grade", "specialty", "model"] as const
export type CastField = (typeof CAST_FIELDS)[number]
/** the fields the editor changes; name and archetype have no server route, so they only show */
export const EDITABLE_HERE = ["look", "soul", "voice", "grade", "specialty", "model"] as const

export type CastSeat = { name: string; archetype: string | null; model: string | null; voice: string | null; hasSoul: boolean; hasLook: boolean }
export type CastCell = { field: CastField; value: string; editable: boolean }
export type CastRow = { name: string; cells: CastCell[] }

export function castRows(seats: readonly CastSeat[], cast: Cast): CastRow[] {
  return seats.map((s) => {
    const value: Record<CastField, string> = {
      name: s.name, archetype: s.archetype ?? "none",
      look: s.hasLook ? "custom look" : "seeded look",
      soul: s.hasSoul ? "has a soul" : "no soul yet",
      voice: s.voice ?? "no persona",
      grade: cast[s.name]?.grade ?? "unset",
      specialty: cast[s.name]?.specialty ?? "unset",
      model: s.model ?? "the archetype's",
    }
    return { name: s.name, cells: CAST_FIELDS.map((field) => ({ field, value: value[field], editable: (EDITABLE_HERE as readonly string[]).includes(field) })) }
  })
}

/** the next entry of a vocabulary after `cur`, wrapping; a value not in it starts at the first */
export const nextTrait = (vocab: readonly string[], cur: string): string => vocab[(vocab.indexOf(cur) + 1) % vocab.length]!

/** a fresh grade or specialty from the hall's own generator: roll()'s fields are independent hashes of the seed,
 * so reading one is the same as rolling with the others locked */
export const rerollTrait = (seed: string, field: "grade" | "specialty", vocab: Vocab): string =>
  roll(seed, { taken: [], vocab })[field]
