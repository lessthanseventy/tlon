## Verdict: APPROVE (one non-blocking correction owed on ticket #9)

### Diff reviewed
`server/config/support/test_database_name.exs` (new), `server/config/test.exs` (refactor),
`server/test/server/test_database_name_test.exs` (new) — commit ee47abb on
`work/dbconnection-client-exited`, rebased onto main's `03413a6` (the actual root-cause fix:
per-checkout test database naming).

### Spec/plan compliance
- Matches the operator's build-stage redirect (msg 2463): extract the inline naming logic into
  a plain function and pin it with a regression test, since config files can't be run by ExUnit
  directly.
- `Server.TestDatabaseName.compute/2` is a faithful extraction of the original inline logic in
  `config/test.exs` (confirmed against `main`'s prior version): same regex, same slice/replace,
  same `env || computed` precedence (`if env` is equivalent since only `nil` is falsy —
  `env = ""` still wins, matching the old `"" || test_database` behavior).
- `Code.eval_file` at config-load time makes the module available for the rest of the VM's
  lifetime (including later ExUnit compilation), which is why the module loads without being
  under `lib/` — reasonable, minimal mechanism for the stated constraint.
- Four tests cover: worktree path → `tlon_test_<name>`, non-word-char folding, main checkout →
  `tlon_test`, and `TLON_TEST_DATABASE` override. Matches all branches of `compute/2`.
- The actual bug fix (per-checkout DB naming) already landed on `main` at `03413a6` before this
  branch rebased onto it — this workline correctly did not re-implement it, only added the
  regression test per plan.md's "no code fix left, only verification + this test" framing.
- `server:check` gate passed (verify evidence recorded, artifact_ok) — confirmed in thread
  history, not just self-reported.

### Finding (non-blocking, fix on the ticket record, not the code)
**The build stage's reported verification used the wrong grep string, so it doesn't prove what
it claims.** daneri's message (id 2464, fact #227) reports "grep 'client exited' across all 6
logs: 0" as evidence the fix eliminated the disconnects. But plan.md explicitly warned against
this exact string (plan.md:53-56): the real log line is `client #PID<0.21885.0> exited` — the
substring `"client exited"` never appears contiguously, so `grep -c "client exited"` returns `0`
unconditionally, whether or not the bug reproduced. This is the identical counting mistake the
plan called out from earlier in the investigation ("the counting bug this agent made earlier...
don't repeat it") — it recurred in the build stage's own report.

This doesn't block merge: the code change is correct and independently gated by the real
`mise run check` / server test suite passing clean, which is the evidence that actually matters.
But the "6 runs, 0 client-exited" claim heading toward ticket #9's durable record is not
evidence of anything and should not be cited as confirmation. Before closing ticket #9, re-run
the two-worktree verification grepping `DBConnection.ConnectionError` (per plan.md's exact
instruction) and record the real count, or drop the unverified claim from the ticket.

### Everything else
No correctness, security, or scope issues in the diff itself. No speculative abstraction, no
unrelated changes. `spawn_ready_timeout_ms` was correctly dropped per the operator's instruction
once the diagnostic disproved that hypothesis.
