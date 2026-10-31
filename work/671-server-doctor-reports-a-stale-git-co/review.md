APPROVE — doctor reports a stale .git/config.lock (#671)

Read the diff (doctor.ex, server.doctor.ex, doctor_test.exs, AGENTS.md, pr.md). `menard run test --in server test/server/doctor_test.exs`: ok, 17 tests, 0 failed. I did not run the full gate.

- `Server.Doctor.config_lock/2` reports `stale … rm <path>` only when the lock is older than 300s and no `bwrap` is running. Otherwise, including no lock, it says `ok`.
- It errs toward `ok`: a missing `pgrep` binary counts as "bwrap running" (the `rescue ErlangError -> true`), and any bwrap on the box suppresses the report.
- The `bwrap_running?` function is injectable, so the four tests (no lock, stale, young, live sandbox) are deterministic.
- The moduledoc says the check can't be trusted inside a seat. That matches the sandbox behaviour in AGENTS.md.
- AGENTS.md now carves out an exception to "never rm the lock", for the operator only, and names `server:doctor`. The doc change is in the same commit as the code.

Notes, none blocking:
- AGENTS.md is touched. If the merge gate treats that as a limit, it is the intended doc sync, not a surprise.
- The 300s threshold is only the constant `@stale_lock_seconds` plus the AGENTS.md wording "a few minutes". Nothing ties them together, so a change to one needs a change to the other.