Closes #766.

The mise stub in `workline_verify_script_test.exs` dumped branch mode's variables to `$GATE_LOG.env`
for the #620 assertion. A seat's sandbox bind-mounts `/dev/null` over every `*.env` it finds at
launch, so a `gate.log.env` left under `server/tmp` from one run made the next sandboxed run's tmp
cleanup (test_helper's `rm_rf`, ExUnit's per-test `tmp_dir` reset) fail "file busy", and the gate
could not go green from a seat. Tolerating busy mounts in the cleanup cannot work (the test's own
`tmp_dir` reset would still fail), so the fix is the name: the sidecar is an env dump, not a dotenv
secret file, and is now `gate.log.vars`. A new test asserts the gate leaves no `*.env` under its tmp
(red before the rename, green after), so the collision cannot come back unnoticed.

Checked: `menard run test --in server test/server/workline_verify_script_test.exs` (32 tests green,
no `*.env` and no mounts under `server/tmp` after it), then the ticket's repro, a sandboxed
`menard run check --in server` from the seat.
