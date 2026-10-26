# Review — release-status-ignores-hand-run-check-ma @ 5db8415

**Verdict: approve.** The change does what ticket #523 asks: a hand-run `check:main` / `release:smoke` now lands as a schedule-less `ScheduleRun` that `Server.Release.Candidate` already reads, through `POST /api/release/ran` and `scripts/lib/record-ran.sh`. Exact-sha matching is unchanged. Gate green on 5db8415 (verify run, server-recorded).

## What I verified, numbered

1. **Nil `schedule_id` breaks no reader.** Every other query on `schedule_run` is scoped by schedule or inner-joins it: `Schedules.runs/2` (`where r.schedule_id == ^id`), `Room.last_runs/1` (`where r.schedule_id in ^ids`), `Release.PM.running?/1`, `Staffing.duty_threads/1` (`join: s in assoc(r, :schedule)`), `Jobs.Orphans.interrupt_runs/2` (by run id from a RunSchedule job). The migration's claim, "these stay off the board", holds.
2. **The scheduler's parse is undisturbed.** `Schedules.ran_on/1` scans `~r/^ran-on: (\S+) ([0-9a-f]{40})$/m`; the new `recorded: gate <sha> exit 0 (…)` line printed after it does not match. The nightly now writes two rows per sha (its own, plus the script's POST), both the same status, the scheduled one newest. Harmless, and pr.md says so.
3. **No test reaches the live service.** Both scripts `unset` every `TLON_*` before `record_ran` runs, so it always posts to `127.0.0.1:4040`. The check-main script test stubs `mise run check` to sleep and kills it: the TERM trap exits 143 before `record_ran`. The smoke tests under `TLON_SMOKE_URL` have an empty `sha`, so the `if [ -n "$sha" ]` guard skips the post; the scratch-repo smokes never reach `smoke passed`.
4. **Input validation is complete for the API's shape.** `record/3` refuses a check outside `gate|smoke`, a sha that is not 40 lowercase hex, and a non-integer exit, and the route maps each to a 422 with the expected shape in the message. Gateway test covers 201, bad sha and missing exit.
5. **Trust stance unchanged.** `/api/*` is loopback and unauthenticated by design (`OperatorAPI` moduledoc); a seat's sandbox cannot reach 4040, so a coworker cannot mark a sha releasable. Same reach as `POST /api/schedules/:id/run` already had.
6. **TestDB cleanup order is right.** `Server.ScheduleRun` is deleted before `Server.Thread` (it has `thread_id`); no `Server.Schedule` entry exists in the list, so no FK ordering issue is introduced.
7. **`check-main.sh` records its real exit** (`code=${PIPESTATUS[0]}` → `record_ran gate "$sha" "$code"`), so a red hand gate reads `failed`, and `record_ran` returns 0 so a down service never changes the gate's exit. `scripts/record-ran.test.sh` covers both branches and is wired into `check:names`.

No spec.md or plan.md on the branch: the workline opened at build from the ticket, which is expected.

## Non-blocking (filed as follow-ups)

See follow_ups: a typo in the `check:names` description, a stale-by-omission sentence in root AGENTS.md, the smoke's pass-only recording, and a dead `TLON_URL` knob in `record-ran.sh`.