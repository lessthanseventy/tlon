# Review — toy step 7: the cast reacts to events, in voice

**Verdict: approve.**

The branch's own diff (6 commits over merge base 88628bb) is 12 files, all `office/`, +362/-11.
The large server/script "deletions" seen diffing against origin/main are this branch sitting
behind main — origin/main landed a landing/review refactor plus a person-brackets office change
after the branch was cut. The merge gate rebases, so none of that is part of this change.

## Spec compliance
- 11 seats × 5 events × 2 lines = 110, each in the §2 voice; uniqueness enforced by test. ✓
- A `react` beat asks each idle seat (sheriff first) 20 ticks apart through a `Sim.reactLine`
  hook that is null by default, so seeded/golden traces don't move. ✓
- Thinking seats (excluded from `r.idle` at event start) are never asked; enforced by test. ✓
- Nina: zoo/meteor/power/duck (the drill keeps her zoomies); Argos: all five, overjoyed at the
  zoo. `WideRoom.reactPets` overrides to add Argos; `Sim.reactPets` is Nina-only. ✓
- Presentation only: react beats call only `this.say`; `onEvent` and the server are untouched, and
  "an event touches nothing the server owns" stays green. ✓
- Task 5 (Nina on the fridge) intentionally not built; noted in pr.md. ✓
- Gate green on branch: `mise run check` 11 passed / 0 failed / 2 skipped; verify evidence recorded.

## No blocking findings
`reactLine` is null in every seeded test, so determinism is preserved. Every stagger window
(≤ b.at + 20·11 = ≤340) fits inside its event's tick budget. The hook is wired for both WideRoom
and RailRoom in `room()`. Generic beats and react beats don't fight for the same seat at the same
tick; where a later generic beat (e.g. zoo's "Order! ORDER!" at 300) replaces a seat's react
balloon, that is the accepted `say`-replaces behaviour called out in the plan.

## Non-blocking
- `pets.test.ts` wraps the Nina/Argos event-line assertion in `chance(0.999, …)`. If
  `this.line`/`bucketFor` ever returns a non-event bucket line for Nina, the test fails ~1-in-1000.
- Drill seat-reactions aren't exercised at the sim level — the stagger and thinking-seat tests
  skip drill (it evacuates the room). The seat-voices data and Argos' drill line are tested; the
  seat react beat during a drill is not.