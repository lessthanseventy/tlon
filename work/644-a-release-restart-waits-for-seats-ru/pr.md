Release restart waits for seats' run_task gates (#644)

`Rollout.busy/0` read only the `verify` and `landing` queues. A seat's `run_task(check)` runs on `tasks`, so a cut made while one was running saw nothing busy, and systemd killed the gate (exit 143) on the thread. `busy/0` now names a running RunTask job too: "the check of #<tid> for <agent> is running".

Ticket: #644.

Checked:
- Red first: the new case in `rollout_test.exs` ("a seat's running check (run_task) is named") failed with `busy/0` returning `[]`.
- Green after the one-line queue change plus its label: `rollout_test.exs` 12 tests, 0 failures.
- `server:test` on the committed head (run_task, result on the thread).
