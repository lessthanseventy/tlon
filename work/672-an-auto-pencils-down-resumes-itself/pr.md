Auto pencils down (#403) now resumes itself: closes #672.

`Pause.auto/1` marks its pause `"pause_by" => "auto"` (any other pause change clears it) and, when the window has a `resets_at`, enqueues `Server.Jobs.AutoResume` at that time. The job calls `Pause.auto_resume/2`, which resumes only if the office is still pencils down, the pause is the auto one, and the window's latch holds the same `resets_at`. It never re-pauses, and lights out is never lifted. The lobby notice says "back to work at HH:MM UTC or when you say" when a job is scheduled, else "back to work when you say".

Checked: `menard run test --in server test/server/pause_test.exs` (new tests: job enqueued at resets_at and resumes; stale job after a hand pause no-ops; nil resets_at enqueues nothing; lights out left alone) and `menard run check --in server`.
