Closes #658.

A scheduled check-main / release-smoke run now leaves one record, a red nightly names its failing test whatever the suite, and the gates' Hex home no longer dirties the gated tree.

- `Server.Schedules` runs a script with `TLON_SCHEDULE_RUN=1`; `lib/record-ran.sh` reads it when sourced (check-main and release-smoke unset `TLON_*` later) and posts nothing, since the schedule writes the row from the `ran-on:` line.
- `failures()` moves from workline-verify.sh to `lib/failures.sh`; check-main uses it instead of its ExUnit-only grep (ExUnit, doctest, bun `(fail)` + `error:`, any mise prefix).
- `HEX_HOME` is `<checkout>.hex`, beside the tree, in check-main, release-smoke and workline-verify; each removes it on exit and the sweeps remove it with its tree. An in-tree `.hex/` made the tree dirty, so check.sh never posted `tlon/check`.

Checked: schedules_test (marker in the script's env), record-ran.test.sh (scheduled run posts nothing), workline_verify_script_test (sources the lib), check_main_script_test (new: gated tree `git status --porcelain` empty, Hex home beside it; red on the old script). Full `check` via run_task.
