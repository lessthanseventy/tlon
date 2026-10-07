VERDICT: APPROVE

Scope: single-file change, server/test/server/commits_test.exs (4b6c95a), matches the goal exactly — "TLON_THREAD env leaks into CommitsTest from the outer session." No production code touched; this is a test-isolation fix, which is the right size for the bug (the leak was in the test harness's `env:` usage, not in `Server.Commits` or the git hooks themselves).

Correctness:
- Root cause as described checks out: `System.cmd/3`'s `env:` option adds/overrides on top of the inherited process env, it does not replace it, so a pane with `TLON_THREAD`/`TLON_AUTHOR` already set leaks those into "no env" test commits and trips the pre-commit branch fence on `main`.
- `isolate_env/1` defaults both keys to `nil` then `Map.merge`s the caller-supplied env on top, so an explicit `{"TLON_THREAD", "42"}` in a test still wins, and anything not supplied is force-unset. `System.cmd` treats a `nil` value in `env:` as "unset in the subprocess" (documented Elixir behavior), so this does what it claims.
- Applied uniformly: `git = fn args, env -> ... isolate_env.(env) end` wraps every call through the test's single `git` helper, including `init`/`config` (called with `[]`), so there's no path that skips isolation.
- The four existing tests' env expectations are unaffected: tests that want `TLON_THREAD` set still pass it explicitly and get it; tests that assert "no env → no Tlon- trailer" are now actually guaranteed that instead of accidentally depending on the outer pane's env being empty.

Verification: I could not independently run the suite here — `menard run test --in server server/test/server/commits_test.exs` fails in this sandbox on `DBConnection.ConnectionError ... not owner` against the Postgres socket, which is a sandbox/permissions artifact unrelated to this diff (app boot requires a DB connection the sandboxed shell can't reach). daneri reported `menard run test --in server test/server/commits_test.exs` green (5/5) and `menard run check --in server` green (922/0) from inside the staffed thread, and the brief's own check log shows `mise run check` passing at 2026-10-07T09:46:51Z, right after the commit — consistent with daneri's claim, not independently re-verified by me.

Note (not blocking this review): branch work/tlon-thread-env-leaks-into-commitstest-f is based on an older main — `git merge-base main HEAD` sits several commits behind current main (762b4f6 et al.). That's a landing-stage rebase concern, not a defect in this diff.

No findings against spec compliance, bugs, or security.