// The hiring hall's card as rows: three views of the candidate (half-block pixels) beside one row per
// field and per part slot. Pure — main.ts owns the keys and the state.
import type { Candidate, Field, Locks } from "../kit/hall"
import { SLOTS, type Slot } from "../kit/parts"
import { ROLE } from "../kit/palette"
import { figure, paints, shirtOf, type Dir } from "../kit/sprites"
import type { Seg } from "./term"

export type RowLock = { kind: "fields"; key: Field } | { kind: "slots"; key: Slot } | null
export type HallRow = { segs: Seg[]; lock: RowLock }

const VIEWS: Dir[] = ["down", "left", "up"]
export const HALL_ROWS = 5 + SLOTS.length

export const stepRow = (i: number, d: number) => (i + d + HALL_ROWS) % HALL_ROWS

/** the figure's pixel rows folded two to a cell: top pixel in the glyph's colour, bottom in its background */
function halfBlocks(px: string[], paint: Record<string, string>): Seg[][] {
  const out: Seg[][] = []
  for (let y = 0; y + 1 < px.length; y += 2) {
    const segs: Seg[] = []
    for (let x = 0; x < px[y]!.length; x++) {
      const top = px[y]![x]!, bot = px[y + 1]![x]!
      const t = top === "." ? undefined : paint[top], b = bot === "." ? undefined : paint[bot]
      if (t && b) segs.push({ s: "▀", fg: t, bg: b })
      else if (t) segs.push({ s: "▀", fg: t })
      else if (b) segs.push({ s: "▄", fg: b })
      else segs.push({ s: " " })
    }
    out.push(segs)
  }
  return out
}

export function hallRows(c: Candidate, locks: Locks): HallRow[] {
  const paint = paints(shirtOf(c.archetype), c.look)
  const views = VIEWS.map(d => halfBlocks(figure(c.look, c.archetype, false, false, d, "stand", 0, false), paint))
  const left = (i: number): Seg[] => views.flatMap((v, n) => [...(n ? [{ s: "  " }] : []), ...(v[i] ?? [{ s: " ".repeat(12) }])])
  const label = (l: string, v: string, locked: boolean): Seg[] => [
    { s: l.padEnd(11), fg: ROLE.inactive }, { s: v }, ...(locked ? [{ s: "  locked", fg: ROLE.meta }] : []),
  ]
  const field = (f: Field, l: string): { segs: Seg[]; lock: RowLock } => ({
    segs: label(l, c[f], !!locks.fields?.includes(f)), lock: { kind: "fields", key: f },
  })
  const body = [
    field("name", "name"), field("archetype", "archetype"), field("grade", "grade"), field("specialty", "specialty"),
    { segs: label("pitch", c.pitch, false), lock: null as RowLock },
    ...SLOTS.map(s => ({ segs: label(s, c.look.parts?.[s]?.id ?? "none", !!locks.slots?.includes(s)), lock: { kind: "slots", key: s } as RowLock })),
  ]
  return body.map((r, i) => ({ segs: [...left(i), { s: "   " }, ...r.segs], lock: r.lock }))
}
