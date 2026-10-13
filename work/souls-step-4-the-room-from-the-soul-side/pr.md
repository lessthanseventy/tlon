# Souls step 4 (room half): the room from the soul

Ticket #63 · thread #265 · design `docs/plans/2026-10-08-souls-design.md` §2–3, §6 step 4.

A soul's People section now steers who pairs up in the office. `office/kit/company.ts` (new, pure)
reads the three verbs the soul template uses — admires / needles / would cover for — against the
bench and answers friend / rival / none. In `sim.ts`, `idleGoal` never takes a pair spot beside a
rival and prefers one beside a friend; `highFives` skips rivals. A seat with no People section
(or a reworded one) behaves exactly as before.

Regex, not a model call: free and deterministic; a reworded soul simply yields no affinity.

**Not in this PR:** the side-projects half (server corkboard notes from "The side project"),
which needs #264's soul reader.

Checked: `mise run office:check` — 541 tests, 0 fail. New: `office/test/company.test.ts`,
a `company` block in `sim.test.ts` (rivals never take the pair spot over 200 choices; friends
strictly more than strangers; no-People seat's picks identical to no souls), and a high-five case
in `pastimes.test.ts`. The wide-room drive (needles pair never share foosball) needs a kitty-graphics terminal and was not run.
