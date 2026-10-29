stop_smoke now cancels a smoke that is still building or queued, instead of only reporting it (closes #536).

- `Server.Jobs.Smoke` stamps `os_pid` and `log` into the job's meta right after `Port.open`, not only when the script holds.
- `Server.Smoke.stop/1` falls through from the held smoke to the building one: an executing job with a pid gets `kill -TERM` (release-smoke.sh traps it and cleans up); an available/scheduled job is cancelled with `Oban.cancel_job/1`.

Checked: two new tests in `jobs/smoke_test.exs` (stop mid-build ends the job with "ended (exit 143)"; stop cancels a queued job) failed before the change and pass after; the file is 20/20. Live check (start_smoke, stop_smoke during a build) is left to QA.
