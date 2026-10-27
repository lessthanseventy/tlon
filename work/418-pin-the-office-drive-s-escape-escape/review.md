APPROVE.

Test-only change to `server/test/server/release_smoke_script_test.exs`. I read the diff; I did not re-run the suite.

- `driven_args/1` is the existing drive run lifted out unchanged. The old "waits for the title" assertions are kept.
- The new test anchors on `Enter` and matches `[_wait, "Escape", "Escape", "c" | _]`. That pins order and count, so dropping one Escape fails it.
- The RED/GREEN and gate numbers (26 tests; gate 2266, 0 failures) are from the builder's PR description; I haven't reproduced them.
- `scripts/release-smoke.sh` is untouched.

No blocking findings.