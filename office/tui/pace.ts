/**
 * A timer's body that runs on every tick while the terminal is focused and, unfocused, at most once
 * per `idleMs`: nothing is watching, so polling at full rate only costs a core.
 */
export function paced<A extends unknown[], R>(focused: () => boolean, idleMs: number, fn: (...a: A) => R, now: () => number = Date.now) {
  let last = now()
  return (...a: A): R | undefined => {
    const t = now()
    if (!focused() && t - last < idleMs) return undefined
    last = t
    return fn(...a)
  }
}
