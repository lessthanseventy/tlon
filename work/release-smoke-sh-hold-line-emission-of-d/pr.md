Closes #440.

- Job test: the stub prints the real hold line with `(dir …)`; the test asserts `meta["dir"]` is recorded, so hold/5's dir capture is exercised end to end.
- Script test: `release-smoke.sh`'s hold line is pinned to `holding <url> up (dir <path>)`.
- `Server.Smoke.drive/3`: a hold with no recorded dir (old hold, or a hold line that drifted from the regex) prefixes the output with `(old hold: driving the checkout's office-drive.sh)` instead of silently driving the checkout's TUI.

Checked: `menard run test --in server` on `jobs/smoke_test.exs` and `release_smoke_script_test.exs` — 44 tests, 0 failures (the fallback test was red first).
