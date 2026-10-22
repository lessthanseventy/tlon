approve

# whimsy-sleep review (round 2)

Round 1 had one blocking finding: `bedScene` matched `/\bbed\b/i`, so "make the bed" (a morning routine from the same §7 doc) put the figure to sleep at 08:00. Fix requested: `/\bin bed\b/i` plus a test that "make the bed" alone yields no scene.

## fixed — verified

2361e02 makes exactly that change:

- `office/kit/life.ts:44` — `/\bin bed\b/i`. "in bed by 23:00" matches; "make the bed" does not.
- `office/test/life.test.ts:69` — new test "making the bed is not going to bed": `bedScene([{ title: "make the bed", … }], …)` → `null`. Closes the gap I flagged (the suite previously only tested "teeth" as the non-bed routine).

The diff since 2c491e8 is these two hunks and nothing else — surgical, no collateral.

## the rest (unchanged from round 1, still holds)

- `BED_ART` silhouettes read without colour — long figure from the pillow vs. short curled cat with ears. Legible for the operator's acuity/double-vision.
- `bed` flows through `HomeView`/`renderHome`/`paintTile` to the bedroom tile only (tested).
- `Date.now()` / `Date.parse(bed.due_at)` comparison is sound; `lifeCard?.today ?? []` guards the missing card.
- office:check green (854 pass, 0 fail); verify passed on the branch.

## non-blocking nit (noted, not filed)

`work/whimsy-sleep/pr.md` (d035d5a, committed after the fix) still says "matched on a routine titled with 'bed'" and "48 pass, 0 fail" — both stale after the regex change (now "in bed", 49 pass in life+homeart). Emma acknowledged this; it's PR-description text, not load-bearing, so no follow-up ticket. If it's easy to refresh before merge, fine; if not, it's history.

Ready to land.