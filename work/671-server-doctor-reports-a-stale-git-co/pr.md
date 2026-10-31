`server:doctor` reports a stale `.git/config.lock`, with the `rm` for the operator to run.

**Why:** a sandbox teardown that dies leaves `.git/config.lock` behind for good, and every git config write after it fails "File exists". Nothing reported it, so the operator found it by hand each time.

**What:** `Server.Doctor.config_lock/2` is a third check beside `crash_dump/2` and `git_fetch_urls/1`. A lock is stale when it is older than five minutes and no `bwrap` is running (`pgrep -x bwrap`, injectable as the second argument so the tests are deterministic). The report names the exact `rm` command. `mix server.doctor` prints it on its `git lock:` line. The moduledoc says the check is honest only on the host. Root `AGENTS.md`'s "never create or `rm` the file" bullet gets the exception: a lock with no sandbox running is stale and the operator removes it.

**Ticket:** closes #671.

**Checked:**
- RED: `menard run test --in server test/server/doctor_test.exs` failed on the four new tests, `Server.Doctor.config_lock/2 is undefined`.
- GREEN: same command, 17 tests, 0 failures. Covers a stale lock with no sandbox (reported, names the `rm`), no lock (`ok`), a young lock with no sandbox (`ok`), and a lock while a sandbox runs (`ok`).
- `menard run check --in server`: format, warnings-as-errors, credo and the full suite, 2522 tests, 0 failures, exit 0. One test (`search_test.exs:139`, FTS over the message channel) was reported flaky in one run and passed in the one that gated; it is not touched by this change.
