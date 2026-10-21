# A smoke that is building is visible

Closes ticket #515 (postmortem: issue #52). `Server.Smoke.held/1` only saw a smoke with a url, so a build in progress was invisible: QA re-queued against its own build and the nudger paged the sheriff.

- `Server.Smoke.building/2`: the thread's queued/running smoke job with no url yet.
- `drive_smoke` / `stop_smoke` answer "building since <t> (job N)" instead of "no smoke is up".
- `start_smoke` for the same ref while one builds returns that job, not a second build the script refuses.
- `Continuation` treats a building smoke as waiting, like a verify job.

Checked: new tests in `jobs/smoke_test.exs` and `workline_continuation_test.exs` (red first, then green); `menard run check --in server`.
