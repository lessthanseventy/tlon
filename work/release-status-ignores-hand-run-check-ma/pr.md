release:status counts a hand-run check:main / release:smoke

`Server.Release.Candidate` read only scheduler-made `ScheduleRun`s, so a tip gated and smoked by hand
still read "not releasable" until the nightly. Now `check-main.sh` and `release-smoke.sh` end by
reporting their `ran-on` result (`scripts/lib/record-ran.sh`) to a new `POST /api/release/ran`, which
calls `Candidate.record/3`: a schedule-less run (migration drops `schedule_run.schedule_id NOT NULL`)
that `Candidate` already reads. Exact-sha matching is unchanged; a failed gate records `failed`; a
service that is down only warns. The scheduler's own run also reports, a harmless duplicate.

Closes #523.

Checked: Candidate and gateway tests red (record/3 undefined, route 404) then green; `record-ran.test.sh`
(wired into check:names); full check via run_task.
