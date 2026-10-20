import { BOSS_LOOK, lookOf, type Look } from "./sprites"

export type LookOverride = Partial<Look>
let overrides: Record<string, LookOverride> = {}
let gen = 0

/** take the machine's looks.json if it changed — same shape as palette.ts's useRoles */
export function useLookOverrides(o: Record<string, LookOverride>) { overrides = o; gen++ }
export function overrideFor(name: string): LookOverride | undefined { return overrides[name] }
/** the operator's key in looks.json: not a name the hall can hand a coworker */
export const OPERATOR = "operator"
/** what a look edit starts from: the operator's own figure, or a coworker's seeded one */
export const baseLook = (name: string): Look => (name === OPERATOR ? BOSS_LOOK : lookOf(name))
/** the operator at the big desk, with whatever they changed about themselves */
export const bossLook = (): Look => ({ ...BOSS_LOOK, ...overrides[OPERATOR] })
/** bumps on every useLookOverrides call, so a per-actor cache can skip recomputing when it hasn't */
export function looksGen(): number { return gen }

/** the editor's three buffers as a Look.custom: views still all "." are dropped (a blank view would draw an invisible figure), and nothing drawn is no field */
export function trimCustom(bufs: Record<"front" | "side" | "back", string[]>): Look["custom"] | undefined {
  const kept = (["front", "side", "back"] as const).filter(v => bufs[v].some(r => /[^.]/.test(r)))
  return kept.length ? Object.fromEntries(kept.map(v => [v, [...bufs[v]]])) : undefined
}
