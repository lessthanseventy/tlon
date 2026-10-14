# Review — toy step 7: the cast reacts to events, in voice (round 3)

**Verdict: approve.**

Round 2 (254d354) approved the office feature code and the release-smoke double-Esc fix.
This round the branch was rebased to drop 72b1c30 (the release-smoke change, a duplicate of
main's 20d02d4) onto the current origin/main. The toy-step-7 feature code is unchanged; the
diff since 254d354 is main's own work pulled in by the rebase (land.sh, Server.BranchReview /
Server.PRLanding, the `isPicked` bracket refactor, person-brackets.test.ts, workline-verify
branch mode, AGENTS.md/tasks.md docs) — none of it this workline's subject.

## What I verified this round
- Feature commits 9b05313 → 5d4b4fd are byte-identical to round 2: `git diff 254d354..HEAD
  -- office/` shows only main's `isPicked` refactor (drawActors/officeTile/rail brackets), which
  is disjoint from the reaction code (seat-voices data, `reactLine` hook, `reactPets`, room
  wiring). No interaction.
- The duplicate release-smoke commit is gone: `git diff origin/main..HEAD -- scripts/release-smoke.sh`
  is empty. Correct — main already has that two-line change.
- Verify gate is green: `mise run check` exit 0, 11 passed / 0 failed / 2 skipped, verify
  evidence recorded. origin/main (8c72a57) is an ancestor of the branch head (95bfc30).

## The wide.test.ts:72 failure is not this branch
daneri reported `bun test` red on one test ("mid-turn works at a desk…"): `wide.test.ts:72`,
`expect(["couch","cooler","coffee","roam"]).toContain(at("w1"))`. I checked:
- `git diff origin/main..HEAD -- office/test/wide.test.ts` is empty — the test is unchanged on
  this branch.
- daneri confirmed it fails identically on a scratch checkout of origin/main, so it is
  pre-existing on main, not a regression from toy-step-7.
- The gate (`office:check`) runs `bun test` at frozen `OFFICE_TEST_HOUR=3` and `=15`;
  daneri's plain `bun test` ran at the real clock. The test is hour-sensitive (cold-seat
  roaming), and verify passed green at the frozen hours — so the failure does not reproduce in
  the gate. daneri filed it as a ticket for main. Not a blocker here, and not a workline
  follow-up (it's a main ticket, not held to this merge).

## Spec compliance (unchanged from round 2, still holds)
- 11 seats × 5 events × 2 lines = 110, each in the §2 voice; uniqueness enforced by test. ✓
- A `react` beat asks each idle seat (sheriff first) 20 ticks apart through a `Sim.reactLine`
  hook that is null by default, so seeded/golden traces don't move. ✓
- Thinking seats are never asked; enforced by test. ✓
- Nina: zoo/meteor/power/duck (the drill keeps her zoomies); Argos: all five, overjoyed at the
  zoo. `WideRoom.reactPets` adds Argos; `Sim.reactPets` is Nina-only. ✓
- Presentation only: react beats call only `this.say`; `onEvent` and the server untouched. ✓
- Task 5 (Nina on the fridge) intentionally not built; noted in pr.md. ✓

## No blocking findings
`reactLine` is null in every seeded test, so determinism holds. Every stagger window fits
inside its event's tick budget. The hook is wired for both WideRoom and RailRoom. Generic and
react beats don't fight for the same seat at the same tick; where a later generic beat replaces
a seat's react balloon, that is the accepted `say`-replaces behaviour called out in the plan.

## Non-blocking (follow-ups, carried from round 2 — still open)
- pets.test.ts wraps the Nina/Argos event-line assertion in `chance(0.999, …)`: if
  `this.line`/`bucketFor` ever returns a non-event bucket line for Nina, the test fails ~1-in-1000.
- Drill seat-reactions aren't exercised at the sim level — the stagger and thinking-seat tests
  skip drill (it evacuates the room). The seat-voices data and Argos' drill line are tested;
  the seat react beat during a drill is not.