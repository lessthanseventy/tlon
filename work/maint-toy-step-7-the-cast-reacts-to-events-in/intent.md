# Intent — maint: toy step 7 (#277) stalled at review

## Originator's words (tlon, message #8716, 2026-10-17 22:30Z)

> breach: workline toy-step-7-the-cast-reacts-to-events-in (#277) has not advanced past
> review within the control band — decide: push it, restaff it, or delete it.

## Restatement

Decide #277's fate — push, restaff or delete — and act on it.

## Where #277 stands (read 2026-10-17 by hronir)

- Branch `work/toy-step-7-the-cast-reacts-to-events-in`, head 94adc63 (origin holds 95bfc30,
  one review-verdict commit behind). Review round 3 (tzinacan): **approve**. Verify green
  (`mise run check` exit 0). No PR yet.
- QA never filed. treviranus (QA, now the thread's lead) could not see the reactions: the
  real office fires events at random and has no key to force one; the sandbox `e` fires one
  but the captured frames showed no Nina/Argos balloon. Asked the operator (#8512); Andrew
  answered (#8592): "Wait: add a forcing key or flag to the real office." treviranus called it
  a builder change and left it; nobody was staffed. Stalled since 2026-10-14 18:13Z.
- The branch is 49 commits behind origin/main and no longer rebases clean: ff5d314 ("office:
  wire seat reactions into the room") conflicts in `office/tui/main.ts` — the one-line
  `room()` constructor that main has since changed. One small conflict.
- Likely why the sandbox frames were empty: Nina's line is said 90 ticks after the event,
  Argos' 40, each seat's at the react beat + 20·i; a frame captured right after `e` is too
  early. Unverified — QA with a forcing key settles it either way.

## Decision: push

The code is approved and green; the only missing artifact is QA, and the operator already
chose how to unblock it. Nothing to delete, and restaffing a review changes nothing. Push means:

1. A forcing flag on the real office (an env such as `OFFICE_TOY_KEYS=1` that enables the
   sandbox toy keys off-sandbox) so `office:drive` can fire a named event on a scratch
   release. Built on #277's own branch, so the QA that needs it drives the same commit.
   Ticket #377 is this gap.
2. Rebase onto origin/main, resolve the `main.ts` conflict, re-verify.
3. QA drives `e` on the scratch release, reads the frames, files `submit_qa`; the operator
   approves at the gate.

Grade: junior for the flag and the rebase (mechanical); the reviewer re-reads the one new commit.
