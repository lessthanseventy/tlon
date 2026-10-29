# Review — a-thread-can-name-its-repo-staff-child-o @ 3f6a18b (round 4)

**Verdict: approve.** All three findings of the earlier rounds are fixed in the ruled shapes; nothing new blocks. Verify's `mise run check` at 02:34 on this head is green (server, adapters, office 934/0).

## Findings

**1. FIXED — `Thread.workline_changeset/1` casts `:repo`** (4484b02), with the MCP workline-path test and the `worktree_for_thread` assertion at `<repo>/.worktrees/<slug>`.

**2. FIXED — a sibling repo's worktree gets tlon's hooks** (88e3d3a). `point_hooks_at_tlon/1` runs from `do_ensure/2` after `git_repo?/1` accepted the path, sets an absolute `core.hooksPath`, checks the git result, is idempotent, leaves `insteadOf` alone. `TLON_THREAD` cleared in `TestRepoDir` and restored on exit.

**3. FIXED — tlon's own repo is recognised from the live node** (3f6a18b). Exactly #16642's shape: `main_root/1` moved from `Smoke` to `Profiles` body-unchanged, `Smoke.script/0` calls it; `point_hooks_at_tlon/1` compares `Profiles.main_root(repo_path)` with `Profiles.main_root()` and targets `<main_root>/scripts/git-hooks`; the commit says why the common dir is the comparison. The test moved to `profiles_main_root_test.exs` and covers the `.release` shape (tmp repo plus a linked worktree resolves to the tmp root). Measured here, not eyeballed: `git rev-parse --path-format=absolute --git-common-dir` from `~/projects/tlon`, from `.release` and from this `.worktrees/` checkout all answer `/home/andrew/projects/tlon/.git`, so on the live node both sides of the comparison are `/home/andrew/projects/tlon` and a tlon thread's `ensure` is a no-op on hooks.

## Verified sound
- `menard run test` on worktree, profiles_main_root, workline and projects tests: 161 tests, 0 failed.
- Every `main_root` caller accounted for: `Smoke.script/0`, `Worktree.point_hooks_at_tlon/1`, the two tests. No other `Smoke.main_root` reference remains.
- Branch is on origin/main (merge-base b8fffdf = origin/main), tree clean.
- No `bench_contrast` row among the CHECKS shown; nothing to call there.