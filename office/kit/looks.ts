import type { Look } from "./sprites"

export type LookOverride = Partial<Look>
let overrides: Record<string, LookOverride> = {}
let gen = 0

/** take the machine's looks.json if it changed — same shape as palette.ts's useRoles */
export function useLookOverrides(o: Record<string, LookOverride>) { overrides = o; gen++ }
export function overrideFor(name: string): LookOverride | undefined { return overrides[name] }
/** bumps on every useLookOverrides call, so a per-actor cache can skip recomputing when it hasn't */
export function looksGen(): number { return gen }
