# Review: merge queue — requeue lost landings, send back red-check landings

**Verdict: request_changes** (one blocking finding, one smaller; the rest reads correct).

Read from `git diff main...HEAD`; I did not run the suite (the gate evidence on the thread shows `mise run check` green).

## Blocking

1. **`Workline.requeue_stranded/0` retries a crashing landing forever.** It requeues any review/open/unawaited thread with a standing approval and no live Land job, every KeepUp tick (~5 min). `Land` is `max_attempts: 3`, and `Land.reported/4` posts to the sheriff on each last-attempt crash. A landing that crashes deterministically (no checkout, raise in the rebase) therefore goes: 3 attempts, discarded, requeued, 3 attempts, discarded… with a sheriff report and a "queued again" brief post each cycle. Before this change it parked once with one report. Bound it: e.g. skip a thread that already has ≥ N discarded `Server.Jobs.Land` jobs for its id (one `Repo.aggregate(:count)` on `Oban.Job` with `state == "discarded"` and `args->>'thread_id'`), and let that last one stay reported. The new test should cover the cap.

## Smaller (fix with the above)

2. **`KeepUp.red_checks/2` reports before it closes.** `Sheriff.report` runs first, and the report says the workline "is back at build" before it is. If `Publish.close` fails (gh error), the PR stays open and failing, so the next tick reports to the sheriff again, every 5 min, with a claim that is false. Close and reland first, report on success (or report once on failure and not again).

## Checked, fine

- `Publish.failing/2`: only `work/*` open PRs, pending is not red, CheckRun `conclusion` and commit-status `state` both handled, unreadable repo → `[]`. Tests cover each.
- `reland/3` default arg keeps the old two-arg callers and the non-merged passthrough.
- `requeue_stranded` correctly voids on a moved branch (via `approval/1`) and does not stack a second job (`landing?/1`).
- Docs: `KeepUp` moduledoc updated; the new sentence is one long line, wrap it.
