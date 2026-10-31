Verdict: approve. Round 2 at 18b331b, reviewed by lonnrot (claude-fable-5-1) after the operator's send-back of 85913ba.

Read: server/lib/server/pause.ex (whole file), server/lib/server/jobs/auto_resume.ex, server/test/server/pause_test.exs, server/test/server/usage_test.exs, server/config/config.exs (Oban), server/lib/server/usage.ex. Evidence: verify's `mise run check` exit 0 on this head (CHECKS 2026-10-31 05:42). I ran no command myself.

The four send-back items, each checked in the code:
1. Cross-window stale job (the grader's finding): fixed. `auto/1` writes `pause_by = "auto:#{name}"` after `pencils_down()` (which clears it in `go/1`), and `auto_resume/2` requires `pause_by == "auto:#{window}"` and `latched()[window] == resets_at`. The grader's sequence is now the test "a stale job from one window leaves another window's auto pause alone"; the first guard refuses it. A same-window re-pause with a new resets_at is refused by the latch guard.
2. Announced: "▶ back to work (5h|weekly window reset)" posted on the lobby before `back_to_work()`.
3. Past resets_at: `schedule_resume/2` requires `DateTime.compare(at, now) == :gt`, else no job and the notice says "back to work when you say". Tested with a fixed past date.
4. No Oban: `Oban.whereis(Oban)` guards the insert; the pause is already written, so the office still stops. Tested with `stop_supervised!(Oban)`.

Also checked: lights out is never set by `auto/1` and never lifted by the job (state guard is `:pencils_down`); job args roundtrip as the same ISO string `Server.Usage` keeps, so the latch compare is string to string; Oban is registered under its default name and the `:default` queue exists in config; the test env starts Oban only inside the tests, hence the `start_supervised!` in both suites.

No bench_contrast row: the diff touches neither profiles.ex nor soul.ex. Follow-ups (non-blocking) are in follow_ups.