Scrub branch mode's variables from the suite that `workline-verify.sh` runs.

**What changed.** `WORKLINE_GATE`, `LAND_REF`, `RUN_TASK` and `RULES_ONLY` were exported into `mise run <task>`, so a suite run under `run_task` inherited the job's branch-mode settings. They are now unset in the `clean` env every suite command runs under, next to the existing `TLON_*` scrub. `CHECKS_LABEL` is left alone; `checks-queue.sh` reads it. The `gate/2` and `verify/2` test helpers no longer carry nil entries for these four, so the test exercises the script, not the helper.

**Why.** Closes #620 (the root fix; the helper-side fix already on main did not reach the script's own environment).

**How it was checked.**
- RED: the new test "the suite inherits none of branch mode's variables" failed with `gate.log.env` = `RUN_TASK=office:test`, `LAND_REF=land/feature`, `WORKLINE_GATE=1`.
- GREEN: `menard run test --in server test/server/workline_verify_script_test.exs` → 30 tests, 0 failed.
- Gate: `menard run check --in server` → 2475 tests, 0 failed, exit 0 (recorded as `check_passed`).

Co-Authored-By: claude-haiku-5-5 <noreply@anthropic.com>
