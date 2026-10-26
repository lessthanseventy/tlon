# Review — release-status-ignores-hand-run-check-ma @ 6dfe14b

**Note: no free reviewer is at the builder's grade (greybeard); tzinacan (deepseek-flash tier) leads this review, so weigh it accordingly.**

**Verdict: approve.**

I read the diff against origin/main (9 commits, 16 files). I did not run the gate; verify and landing do that.

1. `Candidate.record/3` inserts a schedule-less `ScheduleRun`. `ran/3` filters on `check_name` and `sha` only, with no schedule join, so a hand run counts exactly as a nightly does. Exact-sha matching is unchanged. `newest` orders by `finished_at` then `id`, so a later hand pass or fail supersedes an earlier row.
2. `record/3` validates check (`gate|smoke`), sha (40 lowercase hex) and an integer exit. The route maps each failure to a 422.
3. The migration drops NOT NULL on `schedule_id`. The `ScheduleRun` schema has an optional `belongs_to`, and the insert goes through the struct, so no changeset requires it. `down` deletes the null rows first. `TestDB` now clears `ScheduleRun` because nothing cascades these rows away.
4. `record_ran` always returns 0, so a down service never changes a gate's exit. `check-main.sh` unsets all `TLON_*` before sourcing it, so it posts to the default 127.0.0.1:4040 and tests can't reach a real service. `record-ran.test.sh` covers the recorded and service-down branches and is wired into `check:names`.
5. `release-smoke.sh` records only a pass and only when `sha` is non-empty. A failed smoke is therefore not recorded, so `release:status` keeps the earlier row or reads "no smoke". That is safe, not wrong.
6. lonnrot's earlier follow-ups, the `check:names` description comma and the AGENTS.md sentence, are fixed in 6dfe14b.

Not verified: the live `POST /api/release/ran` against a running service.
