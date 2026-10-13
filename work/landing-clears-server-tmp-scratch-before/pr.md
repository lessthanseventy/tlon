Landing clears ignored `server/tmp` scratch before its rebase.

**Why:** ExUnit's `tmp_dir` leaves ignored files in `server/tmp`. When a branch has a commit that once tracked one of them (force-added, later `rm --cached`), `git rebase origin/main` refuses to replay it over the ignored copy ("untracked working tree files would be overwritten by merge"). That bounced #256 twice (landing bounces #7231/#7259). The `server/tmp/` ignore line on main (#327) also cures it; this is the landing-side belt-and-braces.

**What:** `Server.Workline.Merge.rebase_in/3` runs `git clean -fdxq -- server/tmp` in the worktree before the rebase. One file plus its one test.

**Closes:** issue #31.

**Checked:** new test in `workline_merge_test.exs` reproduced the error before the line (12/13), passes with it (13/13); `mise run server:check` suite 1604 passed, deterministic steering evals 9 passed, `mix format --check-formatted` clean on both files.
