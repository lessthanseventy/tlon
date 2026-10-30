Verify.finish/5 now checks for a closed thread before it acts on a recorded verify result.

Before: a red `verify` check recorded after a workline was closed still paged the sheriff and sent the closed workline back to build. The closed clause sat after the "recorded since the run began" clause, so it never got a say.

After: a closed thread is cancelled whatever it recorded, green or red. It is neither moved nor reported. A green result on a closed thread is also cancelled now (it was `:ok` before); that is intended.

Closes #577.

Checked:
- New test "a red result on a thread closed while it ran is cancelled: it stays closed, nobody is told" goes red before the change (`:ok`) and green after (`{:cancel, _}`).
- `menard run test --in server test/server/jobs/verify_test.exs`: 10 tests, 0 failures.
- Related suites (send_back, continuation, workline, rollout, attention_stall) green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
