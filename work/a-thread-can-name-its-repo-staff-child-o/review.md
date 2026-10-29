# Review — a-thread-can-name-its-repo-staff-child-o @ 4484b02 (round 2)

**Verdict: request_changes.** Finding 1 of the first round is fixed on the branch. Finding 2, which hronir ruled a precondition for this diff (msg #16614, restated #16624), is not on the branch: it sits uncommitted in the thread's worktree, half done. The stage moved to review out from under that work.

## Findings

**1. FIXED — `Thread.workline_changeset/1` now casts `:repo`.** The diff since 668b487 is the one-line cast plus `workline_test.exs` "open keeps the repo a workline names". Measured:

```
menard run test --in server test/server/workline_test.exs:60
{"ok":true,"tests":1,"failed":0}
```

The MCP-path test hronir asked for (`staff_child(workline: "build", repo: …)` → `thread.repo` set and `repo_for_thread` resolves to it) exists but is **uncommitted** in `server/test/server/mcp/server_test.exs` ("a workline staffed with a repo keeps it"). It reads correctly; commit it with the hooks work.

**2. BLOCKING, still open — a sibling repo's worktree gets no tlon git hooks.** On the committed branch:

```
git grep -n hooksPath HEAD -- server/lib server/test   → nothing
```

So at 4484b02 a seat staffed on `repo: ~/projects/menard` commits without `Tlon-Thread`/`Tlon-Model` and its own `git push` is unfenced. hronir's ruling stands: in this diff, not #714. The working tree holds the start of it, `Worktree.point_hooks_at_tlon/1` called from `do_ensure/2`, which matches the ruled shape (absolute `<tlon_root>/scripts/git-hooks`, skipped when the repo is `tlon_root`, idempotent, `insteadOf` untouched). Two notes for the finish, so it does not cost another round:
- It has no test yet. The ruled one: ensure against a tmp sibling repo, assert `git config core.hooksPath` equals `<tlon_root>/scripts/git-hooks`; and tlon's own repo is left alone.
- `git(repo_path, ["config", …])`'s result is dropped. If `git/2` returns `{:error, _}` on a failure (an unwritable `.git/config`), ensure proceeds with an unfenced worktree and nobody hears. Pattern-match the `{:ok, _}` or let it fall through to `ensure`'s error, whichever the surrounding code does.
- emma's note (#16626): activating the hooks on tmp test repos made 16 worktree tests fail because `TLON_THREAD` is set in the seat's env and the pre-commit hook refuses commits on main. Fixing the test helper's env is the right scope; don't loosen the hook.

## Verified sound (unchanged from round 1)
- `Projects.workspace_repo/2` validation, `repo_attrs/2` default workspace, `push_branch` untouched and no `push_branch(workspace:)` added.
- CHECKS: the server's `mise run check` at 02:00 is green, but its tail says `tlon/check: not posted — the tree has uncommitted or untracked changes`, so it vouches for no commit; the landing re-gates anyway.
- No `bench_contrast` row, nothing to call there.
