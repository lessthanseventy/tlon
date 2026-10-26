APPROVE — #644 (busy/0 holds for run_task, smoke, scheduled runs).

Reviewed the three work commits (37a229d..b66abda: rollout.ex, rollout_test.exs, workline_verify_script_test.exs, server/AGENTS.md) by reading the diff; I did not run the suite.

Verified against the code:
- Queue names `tasks`, `smoke`, `schedules` match config/config.exs and the workers' `use Oban.Worker, queue:`.
- `job_line/2` reads only keys those workers carry: RunTask `thread_id`/`agent`, RunSchedule `run_id`, Smoke `thread_id`. The new tests assert the lines.
- `RUN_TASK => nil` in the verify-script helper keeps an inherited env var out of the test: a one-line fix, in scope.

Non-blocking (follow-ups):
- The `busy/0` @doc repeats itself.
- A QA *hold* smoke lives until stop_smoke or the 7200s TTL, so it now blocks restart and the restart half of release:cut for up to 2h. Defensible (a restart kills it), but worth a decision.