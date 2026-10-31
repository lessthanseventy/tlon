# Review: approve

- `scripts/workline-verify.sh`: `clean+=(-u WORKLINE_GATE -u LAND_REF -u RUN_TASK -u RULES_ONLY)` strips branch-mode variables from the suite's env only. The script's own `role=` check reads the parent env, so landing mode is unaffected.
- `workline_verify_script_test.exs`: the fake gate records those four variables to `$GATE_LOG.env`, which asserts the scrub. The `gate/2` and `verify/2` helpers set `RUN_TASK`, `LAND_REF`, `RULES_ONLY` and `WORKLINE_GATE` to nil again, so a suite run under a landing no longer leaks them into branch-mode tests.
- Surgical, with the why commented. The diff is small and traces to #620.
- I read the diff only. I did not run the suite, and rely on the builder's red/green claim in 91ccdb3.