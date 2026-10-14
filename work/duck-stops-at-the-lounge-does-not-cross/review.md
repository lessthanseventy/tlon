Verdict: APPROVE

Diff: f985e02 + a2dd247 (office/kit/events.ts, office/test/events.test.ts, pr.md). Closes #349.

Spec: toy-step-5 says the duck "walks in at the door, crosses the hall, looks around, leaves". It stopped at `leftX + 80` (the lounge's left side). Now it crosses to x=12. Verified against the room: the wide room's hall runner is drawn from x=0 to W (wide.ts:388), the duck sprite is 8px wide and blitted centred (zoo.ts:42), so at x=12 it spans 8–16, on the runner, clear of the wall. The rail room stages no events (tested), so the hardcoded endpoint cannot land it anywhere else.

Correctness: the three branches (cross, look round, walk back) all moved to the same `far` constant, so there is no discontinuity at t=300 or t=380. `leftX` is still used by the zoo (events.ts:75,78), so Geo is not left with a dead field.

Test: asserts min x over ticks 120–380 ≤ 12; builder reported red-first at 142. Re-ran here: `bun test test/events.test.ts` 20 pass, 0 fail (record_check). Builder's full `mise run check` was green end to end (message #7987).

Note, not blocking: `far = 12` is layout knowledge (runner starts at x=0, sprite half-width 4 plus margin) living in the event script rather than in Geo. Fine for one user; if a second scene needs the hall's left end, lift it into Geo then.