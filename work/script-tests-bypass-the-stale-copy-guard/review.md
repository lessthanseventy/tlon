APPROVE — work/script-tests-bypass-the-stale-copy-guard @ 07d0580

Read: `git diff origin/main...HEAD` (2 commits, 2 test files + pr.md).

1. `checks_queue_script_test.exs:10` — `queue/1` now passes `TLON_STALE_SCRIPTS_OK=1`. Same treatment the release-smoke test already gives `smoke/1`. The guard itself stays covered by `fresh_script_test`, so the test isn't losing anything. Correct.
2. `release_smoke_script_test.exs` — all three "gone holder" lock records went from `pid 999999` to `pid 9999999`. 999999 is below this box's pid_max (4194304), so a real process could hold it, `kill -0` would succeed and the lock wouldn't be reclaimed. 9999999 is above PID_MAX_LIMIT (2^22 on 64-bit), so `kill -0` always fails with ESRCH. The parser (`release-smoke.sh:75`, `sed 's/^pid \([0-9]*\) .*/'`) takes any number of digits. `grep 999999 server/test scripts` finds no other lock-pid uses; the remaining hits are unrelated thread/record ids.
3. The comments say why, not what. They don't narrate history.

Verified: `menard run test --in server test/server/{checks_queue_script,release_smoke_script,fresh_script}_test.exs` → `{"ok":true,"tests":30,"failed":0}`.

No findings.