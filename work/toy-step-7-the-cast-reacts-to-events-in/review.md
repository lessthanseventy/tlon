# Review — toy step 7: the cast reacts to events, in voice (round 2)

**Verdict: approve.**

Round 1 (032d174) approved the office feature code; that code is unchanged this round.
The only change since is `scripts/release-smoke.sh` (72b1c30): the smoke now sends two
Escapes after opening a thread, because origin/main's 46cdec6 ("a thread opens with its
reply box focused") — now on this branch — makes the first Esc only leave the reply box
(the card stays), so `c` (crew) was never reached.

## The release-smoke change
Verified the root-cause chain in the TUI, not just emma's report:
- `office/tui/main.ts:627` — "a key while a thread card's reply box has focus: Enter sends,
  Esc leaves the box (the card stays)". `office/tui/reader.ts:155` shows the matching
  "esc leave the box" hint.
- `git merge-base --is-ancestor 46cdec6 HEAD` → yes: the branch already has the
  reply-box-focus change, so the double-Esc is correct for the branch's current state,
  not only post-rebase.
- Sequence is now: Enter (open thread, reply box focused) → Esc (leave box, card stays)
  → Esc (leave card → finder) → c (crew) → Esc → R (reload). Correct and minimal; the
  comment names the reason.

Evidence: emma's release:smoke ran green on the main-based tree bd0f803 with the fixed
script (office drove ✓, wide room ✓, exit 0). I did not re-run it — release:smoke needs
the live server channel, unreachable from a sandboxed bash probe — but the mechanism is
confirmed in code, and the gate (`mise run check`, 11 passed / 0 failed / 2 skipped) is
green on the branch with verify evidence recorded.

## Spec compliance (unchanged from round 1, still holds)
- 11 seats × 5 events × 2 lines = 110, each in the §2 voice; uniqueness enforced by test. ✓
- A `react` beat asks each idle seat (sheriff first) 20 ticks apart through a `Sim.reactLine`
  hook that is null by default, so seeded/golden traces don't move. ✓
- Thinking seats are never asked; enforced by test. ✓
- Nina: zoo/meteor/power/duck (the drill keeps her zoomies); Argos: all five, overjoyed at
  the zoo. `WideRoom.reactPets` overrides to add Argos; `Sim.reactPets` is Nina-only. ✓
- Presentation only: react beats call only `this.say`; `onEvent` and the server untouched;
  "an event touches nothing the server owns" stays green. ✓
- Task 5 (Nina on the fridge) intentionally not built; noted in pr.md. ✓

## No blocking findings
`reactLine` is null in every seeded test, so determinism holds. Every stagger window
(≤ b.at + 20·11 = ≤340) fits inside its event's tick budget. The hook is wired for both
WideRoom and RailRoom in `room()`. Generic and react beats don't fight for the same seat at
the same tick; where a later generic beat replaces a seat's react balloon, that is the
accepted `say`-replaces behaviour called out in the plan.

## Non-blocking (follow-ups)
- pets.test.ts wraps the Nina/Argos event-line assertion in `chance(0.999, …)`: if
  `this.line`/`bucketFor` ever returns a non-event bucket line for Nina, the test fails
  ~1-in-1000.
- Drill seat-reactions aren't exercised at the sim level — the stagger and thinking-seat
  tests skip drill (it evacuates the room). The seat-voices data and Argos' drill line are
  tested; the seat react beat during a drill is not.