# Review — toy-the-weird-end-of-the-parts-catalogue (round 2)

**Verdict: approve**

Round 1's one blocking finding is fixed; the snail follow-up is fixed too. No new issues.

## Blocking

None. Round 1's blocker — `fishbowl` erasing the head inside the glass — is resolved.

## What changed since b4d0d38

- **`fishbowl`** (office/kit/parts.ts:64-68) no longer goes through `hat()`; it builds three views from `mid()` rows, which use only `.` and the glass char — never `_`. Walls (`${d.glass}......${d.glass}`, 8 wide) sit at cols 2 and 9 on the front, the 10-wide rim covers row 3, and the hair rows between the walls are left untouched. Side uses `shift 1`, matching `halo`/`ufo`. The comment states the invariant. This is exactly the shape asked for.
- **`snail`** side view (parts.ts:131) moved from `at(1,…)`/`at(0,…)` to `at(5,…)`/`at(4,…)` — cols 5–6 (row 10) and 4–7 (row 11), on the side torso instead of hanging off the chest to the left. Front/back unchanged on the right shoulder.

## Tests

Two new tests in office/test/weird-parts.test.ts, both test-first (RED then GREEN per the builder):
- fishbowl: no view contains `_` — proves nothing is cleared.
- snail: side-view non-dot cols are all within 3–8 — proves it sits on the torso.

`bun test weird-parts parts stable` → 22 pass, 0 fail. `dials wcag` → 14 pass, 0 fail. The 69125-figure stable sha still matches; `parts.test.ts`'s per-part × per-dial × per-view sweep keeps the new rows in-bounds and 3:1. The server's full verify (mise run check) passed on this branch.

## Follow-ups (non-blocking, replace round 1's)

1. **Eyeball the parts in the look card.** Office law: a frame change is seen, not assumed. A seat can't render the look card, so the ten new parts front/side are unverified by eye — the tests prove structure, not that a duck reads as a duck. Whoever drives the office next should glance at the card.
2. **`halo.glow` and `partyhorn.toot` dials are inert.** Ticket #98 named halo flicker and a horn toot on a high-five as behaviours; both dials exist but drive nothing, by design — they wait on a sim hook. File a ticket for the hook if either behaviour is wanted; until then the dials are harmless dead options.