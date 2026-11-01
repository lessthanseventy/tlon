Verdict: request_changes. No free reviewer is at the builder's grade (senior), so this review is from a reviewer below that grade.

Findings:
1. Blocking: commit 753e2b9 commits a stray file, `work/674-operatorconfig-an-explicit-null-on-a/pr.md`, at the repo root. It is a PR-body draft, not repo content. Remove it from the commit (`git rm` it and amend or add a fix commit), then re-run the gate.

Checked (verified):
- `value/2` with `Map.fetch` + `present/2`: absent key gives the default; null on a nullable knob gives nil (off); null on a non-nullable knob gives the default; an invalid value gives the default. Matches the commit message.
- `put_settings/2`: a nil on a nullable knob is written as null; a nil on any other knob deletes the key. Matches the docs.
- Callers: `staffing.ex` `sweep_long` already handles nil as "off", so the nil path it now reaches is correct. `auto_land_risk` has default nil, so its value is unchanged.
- `menard run test` on `server/test/server/operator_config_test.exs` (this worktree): 16 tests, 0 failures.

Not verified: the full `mise run check` gate. I ran only the one test file.