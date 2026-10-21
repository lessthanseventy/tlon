# Review — toy step 7: the cast reacts to events, in voice (round 4)

**Verdict: approve.**

Round 3 approved the office feature code. This round the branch was rebased onto the
current origin/main (8237592 — 11 commits ahead, merge-tree clean) and gained two commits
that let the real office run the room play keys under `OFFICE_TOY_KEYS=1`, so QA can fire an
event and see the cast react off the sandbox.

## What changed since round 3
- `0cc641a` — off the sandbox, `E` alone fires a scripted event under `OFFICE_TOY_KEYS=1`,
  and only where the focused card has no `E` of its own. Introduced `toyEventKey` + a
  `fireEvent()` helper.
- `53cfcda` — generalized the above: `toyEventKey` → `roomKey` + `ROOM_PLAY`, so D E F T P
  all run on the real office under the flag. N W C still `return false` when `!world` (they
  need the sandbox's fake world). The help card lists `ROOM_PLAY` when not sandbox and the
  flag is on.

## What I verified this round
- **Reaction feature code survived the rebase.** `Sim.reactLine` (the null-by-default hook),
  `reactPets`, the react beat (sheriff first, each seat +20 ticks), and 60 event-voice lines
  in seat-voices.ts are all present. `git merge-tree` against main is clean; the hand-resolved
  conflicts in seat-voices.ts / main.ts / sandbox.ts kept main's additions under the reaction
  wiring.
- **Key dispatch is correct.** `toyKey(k)` runs first (main.ts:2257), but on the real office
  `roomKey(k, detail().actions.some(x => x.key === k), TOY_KEYS)` returns false when the
  focused card claims the key — so the card's own action at main.ts:2260 wins. The sandbox
  path is untouched: `!world` is false, so `roomKey` is never called and all PLAY keys still
  win over a card (the help text "they win over a card's" still holds there). The `if (!world)
  return false` guards inside the N/W/C arms are unreachable on the real-office path (the
  outer guard already returned) — defensive, not a bug.
- **`roomKey` is tested.** sandbox.test.ts covers D E F T P (flag on, card-claims, flag off)
  and the N W C exclusion.
- **Gate is green on 53cfcda.** `mise run check` exit 0, office 788 pass / 0 fail, verify
  evidence recorded (workline:toy-step-7-the-cast-reacts-to-events-in:verify). origin/main
  (8237592) is the merge-base.

## Spec compliance (unchanged, still holds)
- 11 seats × 5 events × 2 lines = 110, each in §2 voice; uniqueness enforced by test. ✓
- `react` beat asks each idle seat (sheriff first) 20 ticks apart through a `Sim.reactLine`
  hook that is null by default, so seeded/golden traces don't move. ✓
- Thinking seats never asked; enforced by test. ✓
- Nina: zoo/meteor/power/duck (drill keeps her zoomies); Argos: all five, overjoyed at the
  zoo. `WideRoom.reactPets` adds Argos; `Sim.reactPets` is Nina-only. ✓
- Presentation only: react beats call only `this.say`; `onEvent` and the server untouched. ✓
- Task 5 (Nina on the fridge) intentionally not built; noted in pr.md. ✓
- The `OFFICE_TOY_KEYS` additions are a QA reach, not in the plan, but they don't violate the
  spec — the flag is off by default and the reactions stay in the room.

## No blocking findings
`reactLine` is null in every seeded test, so determinism holds. Every stagger window fits
inside its event's tick budget. The hook is wired for both WideRoom and RailRoom. Generic and
react beats don't fight for the same seat at the same tick; where a later generic beat
replaces a seat's react balloon, that is the accepted `say`-replaces behaviour called out in
the plan.

## Non-blocking (follow-ups, carried from round 3 — still open)
- pets.test.ts wraps the Nina/Argos event-line assertion in `chance(0.999, …)`: if
  `this.line`/`bucketFor` ever returns a non-event bucket line for Nina, the test fails
  ~1-in-1000.
- Drill seat-reactions aren't exercised at the sim level — the stagger and thinking-seat
  tests skip drill (it evacuates the room). The seat-voices data and Argos' drill line are
  tested; the seat react beat during a drill is not.