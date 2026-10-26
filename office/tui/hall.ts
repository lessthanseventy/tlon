// The hiring hall's card as rows: three views of the candidate (half-block pixels) beside one row per
// field and per part slot. Pure — main.ts owns the keys and the state.
import type { Candidate, Field, Locks } from "../kit/hall"
import { SLOTS, type Slot } from "../kit/parts"
import { ROLE } from "../kit/palette"
import { figure, paints, shirtOf, type Dir } from "../kit/sprites"
import type { Seg } from "./term"

export type RowLock = { kind: "fields"; key: Field } | { kind: "slots"; key: Slot } | null
/** what `e` edits on a row: a text field, the pitch, the soul, or a slot's part */
export type RowEdit = Field | "pitch" | "soul" | Slot
export type HallRow = { segs: Seg[]; lock: RowLock; edit: RowEdit }

const VIEWS: Dir[] = ["down", "left", "up"]
export const HALL_ROWS = 6 + SLOTS.length

export const stepRow = (i: number, d: number) => (i + d + HALL_ROWS) % HALL_ROWS

/** the figure's pixel rows folded two to a cell: top pixel in the glyph's colour, bottom in its background */
export function halfBlocks(px: string[], paint: Record<string, string>): Seg[][] {
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
  const field = (f: Field, l: string): HallRow => ({
    segs: label(l, c[f], !!locks.fields?.includes(f)), lock: { kind: "fields", key: f }, edit: f,
  })
  const body = [
    field("name", "name"), field("archetype", "archetype"), field("grade", "grade"), field("specialty", "specialty"),
    { segs: label("pitch", c.pitch, false), lock: null as RowLock, edit: "pitch" as RowEdit },
    ...SLOTS.map(s => ({ segs: label(s, c.look.parts?.[s]?.id ?? "none", !!locks.slots?.includes(s)), lock: { kind: "slots", key: s } as RowLock, edit: s as RowEdit })),
    { segs: label("soul", soulLine(c.soul), false), lock: null as RowLock, edit: "soul" as RowEdit },
  ]
  return body.map((r, i) => ({ segs: [...left(i), { s: "   " }, ...r.segs], lock: r.lock, edit: r.edit }))
}

/** the soul in one line: its first written line, or that nothing is written under the headings yet */
const soulLine = (soul: string) => soul.split("\n").find(l => l.trim() && !l.startsWith("#"))?.trim() ?? "(blank headings — e writes it)"
