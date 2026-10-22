request_changes

# whimsy-sleep review

One blocking finding; the rest is clean.

## the "bed" match is too loose — "make the bed" puts you to sleep

`bedScene` (office/kit/life.ts:44) finds the first routine whose title contains the word "bed":

```ts
const bed = today.find((r) => /\bbed\b/i.test(r.title))
```

§7 (docs/plans/2026-10-06-home-space-and-dollhouse-design.md:360) names two routine packs: `morning` (…make the bed) and `evening` (…in bed by). Both titles contain the word "bed". `today` is ordered by due_at, so the morning "make the bed" sorts first; once it is stamped, `bedScene` returns `"asleep"` and the figure lies down at 08:00 — not what §7 means by "your figure lies down when it is stamped" (the bedtime routine, "in bed by 23:00"). The routine packs are not shipped yet, but a user can create a "make the bed" routine today via `routine_create`, and the collision is designed into the same doc that specifies this whimsy.

Fix: match the bedtime routine, not any bed — `/\bin bed\b/i` ("in bed by 23:00" matches; "make the bed" does not). Add a test that "make the bed" alone yields no scene, closing the gap the current suite has (only "teeth" is tested as the non-bed routine).

### patch
```diff
--- a/office/kit/life.ts
+++ b/office/kit/life.ts
@@ -42,7 +42,7 @@
 export function bedScene(today: LifeStatus["today"], now: number): BedScene | null {
-  const bed = today.find((r) => /\bbed\b/i.test(r.title))
+  const bed = today.find((r) => /\bin bed\b/i.test(r.title))
```

## the rest

- `BED_ART` silhouettes (long figure from the pillow down vs. short curled cat with ears) read without colour — matches §7's legibility intent and the operator's acuity/double-vision constraint. Good.
- `bed` flows through `HomeView`/`renderHome`/`paintTile` correctly; only the bedroom tile blits it (tested: "only the bedroom has a bed").
- `Date.now()` / `Date.parse(bed.due_at)` comparison is sound; `lifeCard?.today ?? []` guards the missing life card.
- office:check green (853, 0 fail); verify passed on the branch.
- Provenance: commit 492ffee trailers claude-sonnet-5-5, matching emma's seat. Honest.

The change is small and surgical — one regex and one test away from correct for the documented routine set.