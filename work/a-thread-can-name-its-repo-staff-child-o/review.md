# Review — a-thread-can-name-its-repo-staff-child-o @ 88e3d3a (round 3)

**Verdict: request_changes.** Both findings of the earlier rounds are fixed in the ruled shapes. One new blocking finding in the hooks commit: the "is this tlon's own repo" test is wrong on the live node, so tlon's own checkout would not be left alone. hronir confirmed it and ruled the fix (msg #16642).

## Findings

**1. FIXED — `Thread.workline_changeset/1` casts `:repo`.** Plus the MCP workline-path test ("a workline staffed with a repo keeps it": `thread.repo` set and `repo_for_thread` resolves to it) and the `worktree_for_thread` assertion that the checkout lands at `<repo>/.worktrees/<slug>` on a tmp repo. All committed at 88e3d3a.

**2. FIXED — a sibling repo's worktree gets tlon's hooks.** `Worktree.point_hooks_at_tlon/1` runs from `do_ensure/2`, sets an absolute `core.hooksPath`, checks the git result (`{_, 0}` or `{:error, _}`), skips when the repo is tlon's, is idempotent, and leaves `insteadOf` untouched. Test: ensure on a tmp repo sets the value and resets it after it was changed. `TLON_THREAD` is cleared in `TestRepoDir` and restored on exit; the hooks themselves are untouched. `do_ensure/2` is reached only from the `true ->` arm of `ensure/2`, after `git_repo?/1` accepted the path, so the new git call is never the first failure on a bad path.

**3. BLOCKING — on the live node, "is this tlon's own repo" is false for tlon's own repo.** `point_hooks_at_tlon/1` compares `Path.expand(repo_path)` with `Server.Profiles.tlon_root/0`, which is `Path.expand("../../..", __DIR__)`: a compile-time path. The service is compiled in `.release/server` (`scripts/release.sh` line 37), and `.release` is a linked worktree of tlon:

```
$ cat /home/andrew/projects/tlon/.release/.git
gitdir: /home/andrew/projects/tlon/.git/worktrees/-release
```

So on the live node `tlon_root()` is `/home/andrew/projects/tlon/.release`, and a tlon thread's repo `/home/andrew/projects/tlon` does not equal it. Every `ensure` on a tlon workline would run `git -C ~/projects/tlon config core.hooksPath /home/andrew/projects/tlon/.release/scripts/git-hooks`, overwriting the relative `scripts/git-hooks` that `server:setup` sets (tasks/server.toml:24) in the shared `.git/config`. The hooks still run (same repo-agnostic scripts), but tlon's own checkout is not "left alone" as ruled, every tlon worktree's hooks silently become the release's copy, and the suite cannot see it because there `tlon_root` is the source checkout. `Smoke.main_root/1` exists for exactly this gap.

Fix, as ruled in #16642:
- Lift `main_root/1` out of `Server.Smoke` into `Server.Profiles` (body unchanged: parent of `git rev-parse --path-format=absolute --git-common-dir`, default arg `tlon_root()`); `Smoke.script/0` calls `Profiles.main_root()`. A pure move.
- In `point_hooks_at_tlon/1`: `own? = Profiles.main_root(repo_path) == Profiles.main_root()`, and the hooks target `Path.join(Profiles.main_root(), "scripts/git-hooks")`. Any linked worktree of tlon then counts as tlon's own; a sibling's common dir is its own, so it still gets the hooks.
- Test: `Profiles.main_root/1` on a tmp repo plus `git worktree add` of it, asserting the linked worktree resolves to the tmp repo's root (the `.release` shape). Keep the existing sibling test.
- The commit says why the common dir is the comparison: a release built in a linked worktree.

## Verified sound
- `Projects.workspace_repo/2` validation and `repo_attrs/2` default workspace; `push_branch` untouched, no `push_branch(workspace:)` added.
- CHECKS: verify's `mise run check` at 02:20 on 88e3d3a is green (server, adapters, office 934/0). Its tail says `tlon/check: not posted — the tree has uncommitted or untracked changes`, so it vouches for no commit; the landing re-gates anyway.
- No `bench_contrast` row in CHECKS, nothing to call there.