import type { Look } from "./sprites"

export type LookOverride = Partial<Look>
let overrides: Record<string, LookOverride> = {}

/** take the machine's looks.json if it changed — same shape as palette.ts's useRoles */
export function useLookOverrides(o: Record<string, LookOverride>) { overrides = o }
export function overrideFor(name: string): LookOverride | undefined { return overrides[name] }
