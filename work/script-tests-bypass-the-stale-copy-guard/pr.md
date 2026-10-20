Script tests no longer trip the stale-copy guard when origin/main moves mid-run.

`checks_queue_script_test`'s `queue/1` now sets `TLON_STALE_SCRIPTS_OK=1`, as the release-smoke test's `smoke/1` already does (f349377, 5446603): the guard reads the live `origin/main` ref, which moves under the nightly gate and verify, and `fresh_script_test` owns the guard itself.

Closes ticket #462 (issue #41).

Checked: reproduced red in a scratch clone (origin/main moved `checks-queue.sh` → exit 2 without the flag); `menard run test --in server` on release_smoke_script_test, checks_queue_script_test, fresh_script_test: 30 tests, 0 failures.
