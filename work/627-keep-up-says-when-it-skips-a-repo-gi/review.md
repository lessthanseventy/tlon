APPROVE. Right then: the diff reads true.

- `remote/2`: exit 2 → `:none` skip; any other non-zero → `{:fault, …}` through `fault/1`, so the job fails instead of silently skipping. Matching is on the URL alone, no `gh` read, so a down `gh` can't make repos look non-GitHub.
- Keyed note `keep_up:remote:<repo>` is updated in place and cleared on the `:github` branch. The persistent_term log-once is gone; the moduledoc matches.
- Verified: `menard run test --in server test/server/jobs/keep_up_test.exs` → 26 tests, 0 failed. I did not run the full gate (builder reports 2487/0; verify runs it).
- Not verified: the pr.md claim that the new tests went red first.