// The pet store's card as rows: the species' sit and walk frames (half-block pixels) beside one row per field.
// Pure — main.ts owns the keys and the state. tui/hall.ts is the same shape for people.
import { furOf } from "../kit/draw"
import { ROLE } from "../kit/palette"
import { dots, SHADES, slotOf } from "../kit/pets"
import { SPECIES_ART } from "../kit/sprites"
import { labelOf, type Candidate, type StoreRow } from "../kit/store"
import { halfBlocks } from "./hall"
import type { Seg } from "./term"

export type StoreViewRow = { segs: Seg[]; lock: StoreRow | null }
export const STORE_VIEW_ROWS = 8
export const stepStoreRow = (i: number, d: number) => (i + d + STORE_VIEW_ROWS) % STORE_VIEW_ROWS

/** halfBlocks folds two pixel rows to a cell; an odd-height frame gets an empty row under it */
const even = (rows: string[]) => (rows.length % 2 ? [...rows, ".".repeat(rows[0]!.length)] : rows)

/** `occupant` is who the adopt would replace; `line` one line in the species' voice (previewOf) */
export function storeRows(c: Candidate, locks: readonly StoreRow[], occupant: string, line: string): StoreViewRow[] {
  const art = SPECIES_ART[c.species], fur = furOf(c.shade)
  const paint = { k: fur, t: fur, e: ROLE.body, c: ROLE.inactive, w: ROLE.edge, p: ROLE.attention }
  const views = [art.sit[0]!, art.walk[0]!].map((f) => halfBlocks(even(f), paint))
  const left = (i: number): Seg[] => views.flatMap((v, n) => [...(n ? [{ s: "  " }] : []), ...(v[i] ?? [{ s: " ".repeat(v[0]?.length ?? 0) }])])
  const label = (l: string, v: string, locked: boolean): Seg[] => [
    { s: l.padEnd(11), fg: ROLE.inactive }, { s: v }, ...(locked ? [{ s: "  locked", fg: ROLE.meta }] : []),
  ]
  const lockable = (r: StoreRow, l: string, v: string): StoreViewRow => ({ segs: label(l, v, locks.includes(r)), lock: r })
  const body: StoreViewRow[] = [
    { segs: label("species", labelOf(c.species), false), lock: null },
    { segs: label("slot", `the ${slotOf(c.species)} slot — ${occupant} leaves by the door`, false), lock: null },
    lockable("name", "name", c.name),
    ...(["warmth", "wits", "energy"] as const).map((a) => lockable(a, a, dots(c.temperament[a]))),
    lockable("shade", "shade", `${c.shade + 1} of ${SHADES}`),
    { segs: label("says", line, false), lock: null },
  ]
  return body.map((r, i) => ({ ...r, segs: [...left(i), { s: "   " }, ...r.segs] }))
}

/** the adopt confirmation: the slot's occupant leaves, whichever slot it is */
export const adoptAsk = (occupant: string, adopted: string) => `${occupant} leaves by the door. adopt ${adopted}?`
