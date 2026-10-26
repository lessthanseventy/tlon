Release restart waits for seats' run_task gates, smokes and scheduled runs (#644)

`Rollout.busy/0` read only the `verify` and `landing` queues. A seat's `run_task(check)` runs on `tasks`, the nightly gate runs as a schedule run on `schedules`, and check-main runs as a smoke on `smoke`. A cut made while any of them ran saw nothing busy, and systemd killed the gate (exit 143) on the thread. `busy/0` now names each of them:

- "the check of #<tid> for <agent> is running" (run_task)
- "the smoke of #<tid> is running"
- "the scheduled run <id> is running"

`server/AGENTS.md` names the same kinds under `server:restart`.

A test-helper fix rides along: the verify-gate test helper inherited `RUN_TASK` from a run_task job's env and failed the default case, so it now clears `RUN_TASK` unless a test sets it.

Ticket: #644 (and #73 on it).

Checked:
- Red first, each case: the run_task case ("a seat's running check (run_task) is named") failed with `busy/0` returning `[]`; the smoke/schedules case failed with the smoke job not counted.
- Green: `rollout_test.exs` 13 tests, 0 failures; `workline_verify_script_test.exs` 23 tests, 0 failures, also with `RUN_TASK` set in the env.
- `mise run server:test` passed on the committed head b504b79 (run_task, result on the thread).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
