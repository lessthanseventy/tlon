# Review: souls step 4, room half — APPROVE

Branch `work/souls-step-4-the-room-from-the-soul-side`, 5 commits on b35afe3 (origin/main unmoved, no rebase due).

## Spec compliance
- Decision 1 (regex on admires / needles / would cover for, names on the bench): done in `office/kit/company.ts`, pure, folded for case and accents, one clause per verb up to the next verb or period.
- `idleGoal`: a pair spot whose waiting partner is a rival is dropped from `free` before any roll; a waiting friend is taken at 0.9, then the existing 0.7 gate. Free single spots unchanged.
- `highFives`: rivals skipped.
- A seat with no People section picks tick-for-tick as with no souls (tested).
- Side-projects half correctly left out (ticket #323, blocked on #264's reader); pr.md says so.

## Checked
- Symmetry: both ends of chat/foosball/pool carry a mutual `with` (tiles/lounge.ts, tiles/games.ts), and `actor.spotKey` is set when a goal is assigned (sim.ts step loop), so `held` and the partner lookup agree while someone is still walking to an end.
- Cost: `relation()` runs only for pairs already standing within reach in `highFives`; in `idleGoal` the soul work sits after the `until` early return.
- `bun test test/company.test.ts test/sim.test.ts test/pastimes.test.ts`: 53 pass, 0 fail. Verify's `mise run check` green on this sha.

## Non-blocking (follow-ups filed)
1. Spec decision 1 says the card shows a one-line "read by verb" note beside the People section; neither plan nor build has it.
2. `relation()` compares the raw handle against names that `affinities()` folded; a handle with a capital or accent would never match. Harmless today. Also `fold`'s combining-mark class is literal characters; `̀-ͯ` is editor-safe.

## Noted, no action
- Friend gate: spec said "×3 / with certainty", plan pinned 0.9, build is 0.9; the test asserts strictly more than strangers.
- Negation is not read ("never needles X" marks a rival): the accepted cost of regex, per the spec.
- The wide-room drive was not run (needs a kitty-graphics terminal); the pr.md says so.
