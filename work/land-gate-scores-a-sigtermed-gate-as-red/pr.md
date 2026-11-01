Land gate: a gate whose BEAM got SIGTERM is interrupted, not red (closes #693)

mise exits 1, not 143, when the BEAM inside it is TERMed ("[server:check] SIGTERM received - shutting
down"), so `Land.gate_result/1` (exit > 128 only) scored a service stop as a red and bounced #405.

- `Land.gate_result/1` also reads that line in the output as `{:interrupted, _}`.
- `scripts/workline-verify.sh` `run_gate` exits 143 on that line and records nothing, so a verify is
  retried by `Verify.finish` (nothing recorded) instead of getting a `check_failed`.
- Both match the notice only at the end of a line: the same words quoted inside a failing test's
  report (mid-line, followed by `\n** (EXIT`) stay red, so the fix's own test can regress as a red.

Checked: `menard run test --in server test/server/jobs/land_test.exs` → ok, 5 tests, 0 failed;
`bash -n scripts/workline-verify.sh`, and the anchored grep tried by hand on the real notice (matches)
and the quoted shape (ignored). The script path has no test harness; it is unexercised end to end.
