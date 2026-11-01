Land gate: a gate whose BEAM got SIGTERM is interrupted, not red (closes #693)

mise exits 1, not 143, when the BEAM inside it is TERMed ("[server:check] SIGTERM received - shutting
down"), so `Land.gate_result/1` (exit > 128 only) scored a service stop as a red and bounced #405.

- `Land.gate_result/1` also reads that line in the output as `{:interrupted, _}`.
- `scripts/workline-verify.sh` `run_gate` exits 143 on that line and records nothing, so a verify is
  retried by `Verify.finish` (nothing recorded) instead of getting a `check_failed`.

Checked: `menard run test --in server test/server/jobs/land_test.exs` → ok, 4 tests, 0 failed;
`bash -n scripts/workline-verify.sh`. The script path has no test harness; it is unexercised end to end.
