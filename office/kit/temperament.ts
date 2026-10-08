// A pet's three axes (design §5.3), each -2..2. They are policy over the sim's chance tables, not
// new behaviours: a neutral temperament reproduces the tables exactly.
export type Temperament = { warmth: number; wits: number; energy: number }
export const AXES = ["warmth", "wits", "energy"] as const
export type Axis = (typeof AXES)[number]

/** where a pet walks to next, `stepCat`'s table in the order it is read */
export type Dest = "nap" | "desk" | "perch" | "play" | "litter" | "spot"
export const CAT_BASE: Record<Dest, number> = { nap: 0.45, desk: 0.1, perch: 0.15, play: 0.1, litter: 0.05, spot: 0.15 }

export const clampAxis = (n: number) => Math.max(-2, Math.min(2, Math.round(n)))
/** 1 at 0, 0.5..1.5 across the axis: every knob is this one function */
export const lean = (axis: number, strength = 0.25) => 1 + axis * strength

/** energy: lazy → nap, playful → play/perch; wits: dim → aimless `spot`. Normalised to sum 1. */
export function destWeights(t: Temperament, base: Record<Dest, number> = CAT_BASE): Record<Dest, number> {
  const w: Record<Dest, number> = {
    nap: base.nap * lean(-t.energy), desk: base.desk,
    perch: base.perch * lean(t.energy), play: base.play * lean(t.energy),
    litter: base.litter, spot: base.spot * lean(-t.wits),
  }
  const sum = Object.values(w).reduce((a, b) => a + b, 0)
  return Object.fromEntries(Object.entries(w).map(([k, v]) => [k, v / sum])) as Record<Dest, number>
}

/** `r` in [0,1): the cumulative walk over `destWeights` — with neutral weights, `stepCat`'s old thresholds */
export function pickDest(t: Temperament, r: number, base?: Record<Dest, number>): Dest {
  const w = destWeights(t, base)
  let acc = 0
  for (const d of Object.keys(w) as Dest[]) { acc += w[d]; if (r < acc) return d }
  return "spot"
}
