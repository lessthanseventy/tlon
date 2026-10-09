APPROVE

Change: a42ce6c, 2 lines in server/test/server/office/needs_test.exs. The setup now dismisses every Server.Rollout.pending() note before each test.

Verified by reading the code:
- Server.Rollout.pending/0 and dismiss/1 exist (rollout.ex:70, :79). Both return [] / :ok when the GenServer isn't running, so the setup is safe either way.
- Needs reads Rollout.pending() at needs.ex:233. That is the leak the commit message describes, so the fix addresses the cause.

Not verified: I did not re-run the suite. The thread's recorded `mise run check` is green (9 passed, 0 failed).

Nits: none. The comment states a real why (Rollout's notes are global process state). Scope is surgical.