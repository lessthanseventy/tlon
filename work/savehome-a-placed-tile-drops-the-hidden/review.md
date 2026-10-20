## Verdict: approve

Round 4 — re-review of work/savehome-a-placed-tile-drops-the-hidden at 01817cc.

### What changed since the round-3 verdict (a7de6fb ≡ 4fcffae)
`git diff a7de6fb..HEAD -- office/tui/home.ts office/test/home.test.ts` is empty — the saveHome fix and its two tests are byte-identical to what round 3 approved. The only additions on top are check-main test work (ticket #416), authored by pierre:

- `2830104` — `check_main_script_test.exs`: the existing `leftovers(ctx) == []` assert now names the leftover and its contents on failure. Diagnostic only.
- `01817cc` — `check_main_script_test.exs`: a new test that sends a second TERM while the EXIT trap is mid-removal and asserts no leftovers. Red-first; passes against the `trap "" TERM INT` fix.

The fix the new test exercises is **already on main** as `40eae98` (#416), and the branch's base (dc38176) is past it, so `scripts/check-main.sh` on this branch already carries the fix — `git show HEAD:scripts/check-main.sh` lines 16-17 match `origin/main`. The test is green on the branch; no duplicate of the fix is carried.

### saveHome correctness (unchanged, re-confirmed)
`office/tui/home.ts:37-43` — `cells` is the set of placed-tile cells; a hidden unknown tile is dropped iff its `at` is a real array in `cells`. Non-array/missing `at` is kept and `.join` is never called, so the save is no longer cancelled by a malformed hidden tile (the regression round 2 missed and round 3 fixed). `cells` itself is safe: `home.tiles` are `HomeTile`, whose guard requires a length-2 number `at`. Surgical: 4 logic lines + 2 tests, touching nothing outside the cell filter.

### Scope note (non-blocking)
The check-main test additions are #416 work, not saveHome. The operator directed that chase onto #281 test-first (decision 2200 / fact 2228), so they ride this branch by his call; they apply cleanly on rebase (main already has the fix, the test is net-new). Not a reason to hold.

### Gate
Verify recorded `check_passed` on 01817cc (2026-10-20T04:07:41Z, exit 0). `origin/main...HEAD` is the five files above and nothing else.

No follow-ups.