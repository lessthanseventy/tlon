events.test.ts: the "touches nothing" loop asserts event(k) returned true

A refused start made the loop pass vacuously (nothing ran, nothing changed). The loop now
`expect(r.event(k)).toBe(true)` before stepping, so every kind must actually start.

Closes #309 (follow-up from #255).

Checked: `bun test test/events.test.ts` in office/ — 19 pass, 0 fail.
