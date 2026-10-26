# A scheduled run killed by a stop is `interrupted`, not red (#312)

A scheduled script that dies of SIGTERM/SIGKILL (exit 143/137) now closes its run as `interrupted`:
no Sheriff report, and the gate-on-main reader treats the sha as "no check yet" so the next run is
the verdict. Exit 124 and other non-zero codes stay `failed`.

- `Schedules` script work classifies 143/137 as `interrupted`, notes it on the standing thread.
- `Jobs.Orphans` closes a restart-cut run as `interrupted`.
- `Release.Candidate.newest/1` skips interrupted runs.
- Migration adds `interrupted` to `schedule_run_status_check`.
- Office board: `⊘` glyph and type for interrupted (typecheck only; glyph untested).
- `check-main.sh` already exits 143 on TERM (proved with a stand-in; no script change).

Checked: `menard run check --in server` green (2197 tests); office `bun run typecheck` clean.
Closes #312.
