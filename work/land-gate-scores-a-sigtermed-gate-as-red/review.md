# Review: land-gate-scores-a-sigtermed-gate-as-red @ 5c87d9e

No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5), a lower grade.

**Verdict: approve.** The fix commit applies the earlier blocking finding as posted.

- `Land.gate_result/1` returns `{:interrupted, _}` for exit >128 or for a line that ends with the BEAM's SIGTERM notice. The same words quoted mid-line, as in an ExUnit failure report, stay red.
- `run_gate` in `scripts/workline-verify.sh` uses the same line-end anchor (`grep -q '…shutting down$'`) and exits 143 before anything is recorded, so a verify is retried rather than scored `check_failed`.
- A second test pins the quoted-phrase case at exit 1 as `{:error, binary}`.

Checked:
- `menard run test --in server test/server/jobs/land_test.exs` → ok, 5 tests, 0 failed.
- `bash -n scripts/workline-verify.sh` → ok.
- The grep matches a real-shaped notice line (1) and ignores the quoted shape (0).

Not exercised: the script path has no harness, so it was checked only by hand. This is the same limit pr.md states.

Note: the Elixir string branch and the script must keep the same phrase. This is acceptable as it stands.