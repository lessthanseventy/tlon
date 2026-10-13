// One run in flight at a time, at most one queued behind it: a slow server never stacks refreshes,
// and a call made during a flight (a write's follow-up) resolves after a run that began after it.
export function oneInFlight(run: () => Promise<void>): () => Promise<void> {
  let flying: Promise<void> | null = null, queued: Promise<void> | null = null
  const go = (): Promise<void> => {
    if (!flying) return (flying = run().finally(() => { flying = null }))
    return (queued ??= flying.then(() => { queued = null; return go() }, () => { queued = null; return go() }))
  }
  return go
}
