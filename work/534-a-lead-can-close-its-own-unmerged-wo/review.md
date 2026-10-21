# verdict: approve

Round 2. The round-1 blocking bug is fixed, test-first, and the rest of the change holds up on a full re-read.

## round-1 finding — fixed

`finish` with a blank `abandoned`/`superseded_by` on an unmerged workline no longer crashes. The new `{:error, :why_closed} ->` clause in `Finish.execute`'s `else` returns `ok(frame, %{stays_open: true, why: …})`, so a blank reason keeps the thread open and names both fields instead of raising `FunctionClauseError` in `reply/3`.

The fix is cleaner than the one I proposed: I suggested `fail(frame, …)` (which would set `isError`); the builder used `ok` + `stays_open`, which is consistent with the sibling `:workline ->` and lobby `true ->` clauses — a stays-open-with-guidance is the tool correctly refusing to close, not an error. Right call.

RED→GREEN test: `"finish with a blank abandoned … stays open and says why, not a crash"` sends `abandoned: "   "`, asserts `refute r["isError"]`, `stays_open == true`, `why =~ "superseded_by"`, and `state: "open"`. The whitespace path is genuine: `why_closed/1` admits `"   "` (`is_binary`), `close_as/2` trims it blank → `{:error, :why_closed}` → the new clause. Before the fix this raised, so the test was red.

## the rest of the change — sound

`close/2` routes correctly:
- `{false, _}` — not an unmerged workline → `close_thread/1` (unchanged behaviour).
- `{:workline, nil}` — unmerged workline, no why → `:workline` (stays open, the existing guidance, now wording points at the two fields).
- `{:workline, why}` — unmerged workline with a why → `Channel.close_as/2`, the same path `close_thread` uses.

`why_closed/1` precedence: `superseded_by` is matched before `abandoned`, so a caller passing both gets `:superseded` (ticket done) over `:abandoned` (ticket to backlog). Reasonable, and both fields are documented as optional workline-only.

The merged-stage-open thread (`stage: "merged", state: "open"`) is `:workline` to `unmerged_workline?/1`, so it reaches `close_as/2` — but `close_as`'s guard `stage not in [nil, "merged"]` rejects a merged stage and falls to its catch-all `close_thread(thread)`. So merged work closes normally, the why ignored. Correct, and the `unmerged_workline?` merged clause is pre-existing (not introduced here).

Tests cover the two happy paths (abandon → ticket `backlog`; superseded → ticket `done`) and the blank-why guard. Verify passed: `menard run check --in server` → 1964 tests, 0 failures.

## non-blocking notes (carried from round 1, not findings against this change)

- Merged-stage + state-open workline closing normally through `close_as`'s catch-all is pre-existing `close_as` semantics shared with `close_thread` — not introduced here, and merged work closing normally is right. No ticket.
- #80 (abandon doesn't clear the ticket's `promoted` link) is tracked elsewhere and was explicitly out of scope per pr.md. The abandon test here asserts `status: "backlog"` but not `promoted_thread_id`, consistent with that. Left open where it lives.

No open non-blocking findings against this change — no follow_ups.