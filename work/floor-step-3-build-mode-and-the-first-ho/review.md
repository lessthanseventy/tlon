APPROVE

Reviewed the 5-commit diff on work/floor-step-3-build-mode-and-the-first-ho against main (office/kit/home.ts, office/test/home.test.ts, office/tui/home.ts, office/tui/main.ts — 330 lines, no spec.md/plan.md committed for this step, consistent with the brief's "a doc from a stage this workline started after won't exist").

**Spec compliance**
- Build mode engine (`kit/home.ts`): place/pick-up/carry/drop/rotate/remove/undo, all gated correctly — every mutator but `move`/`pickUp` refuses while `carrying` (prevents losing or duplicating the carried tile), matching learning #339/#340.
- Connectivity rule enforced via `connected()` (BFS over grid adjacency) and checked by both `drop` and `place` through `canPlace`; covered by tests for the straightforward and the "stranded tile" cases.
- `writes` counter correctly distinguishes mutations that must persist from in-memory-only ones (`pickUp`/`move`/a refused `drop` don't bump it; `place`/`drop`/`remove`/`rotate`/`undo` do) — this is the fix for the earlier "pick-up writes home.json" bug, and `tui/main.ts`'s `mutate()` only calls `saveHome` when `writes` changed. Verified against home.test.ts's explicit write-count assertions.
- `home.json` IO is cleanly out of `kit/` and into `tui/home.ts`, as intended; load validates tile shape (kind in CATALOGUE, numeric 2-tuple `at`) and drops anything malformed rather than trusting the file — tested with a mixed-garbage fixture.
- TUI surface: `B` opens build mode (uppercase, per decision #338 to leave `b` for memory); arrow keys move, Enter picks up/drops, `n`/`x`/`r`/`u` cycle/remove/rotate/undo, Esc leaves. State persists across leave-and-reopen by design (`build` stays a module-level `Build | null`).

**Non-blocking observations** (not requesting changes for these):
1. `tui/main.ts`'s build-mode grid renders every cell in the bounding box of `[tiles ∪ cursor]`. Nothing clamps how far the cursor can move from the floor, so holding an arrow key can blow the bounding box out to a very wide/tall render. Low severity (single-user local TUI, no crash), but worth a follow-up if it's ever noticeably slow in practice.
2. `place()` (the `n` key, cycling a cell's kind) drops any existing `rot` when it advances to the next kind in the catalogue — rotating then cycling the kind silently resets orientation. Likely fine since there's one tile shape this step, but flagging in case it surprises later.
3. `refused` isn't cleared by `remove`/`rotate`/`undo`, only by `move`/`pickUp`/a successful `place`/`drop` — a stale "refused" banner could in theory survive past the action that caused it. Didn't find a path where this is user-visible given the current action set, but worth a glance if the refused-state UI changes.

**Checks**
- `mise run check` is green on this branch (recorded in the workline evidence), including office:check 124/0 and the two upstream PR #65 fixes applied for the ambient-env/night-owl issues — this branch itself needed no changes to pass.
- Issue #4 (wide.test.ts golden-hash + pastimes.test.ts cold-day path, both deterministic) is confirmed pre-existing on origin/main itself and unrelated to this diff — not a reason to block this review.

Test coverage (office/test/home.test.ts) is thorough: connectivity, overlap, the full build/pick-up/drop/refuse/rotate/remove/undo surface, the 10-entry history cap, the carrying-blocks-mutation invariant, and the home.json round-trip including malformed-file handling. No gaps found that would change the verdict.