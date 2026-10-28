No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (deepseek-flash) from the diff alone.

**Verdict: approve.** Right then: the change reads correct and small. I did NOT run the tests (no Postgres or checks queue in this seat), so the new worktree_test.exs and server_test.exs cases are unverified by me. Verify and landing run the full gate.

Checked in the diff:
- `bring_to_main/1` refuses a half-done rebase, merge or cherry-pick before `catch_up/1`, so it never rebases over a stopped rebase. A conflict runs `rebase --abort` and refuses, leaving the branch as it was.
- `:detached` and `:dirty` map to refusals with a reason. `{:ahead, n}` with nothing new on main returns `:level`, so no pointless rebase.
- `--no-update-refs` pins away the machine's `rebase.updateRefs` setting.
- The MCP tool maps `{:refused, _}` and `{:error, _}` to `fail` and everything else to `ok`. The `thread_id` handling reuses `acting_thread`, as push_branch does.
- The brief and AGENTS.md changes match the new tool.

Notes, none blocking:
- AGENTS.md and the Profiles prompt text changed. The prompt change rolls panes whose launch changed, and an AGENTS.md edit may trip the limit-gates list for whoever approves the merge. That decision is theirs.
- `bring_branch_to_main` posts a notice on every outcome, `:level` included. This is deliberate per its docstring, since the call is asked for.