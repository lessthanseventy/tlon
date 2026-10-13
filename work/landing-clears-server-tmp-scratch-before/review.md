# Review — landing-clears-server-tmp-scratch-before

**Verdict: APPROVE**

Scope matches the ask (scharlach's spec, #7301): one line in `Server.Workline.Merge.rebase_in/3` plus one test, nothing else. `work/…/pr.md` is present and accurate.

## Verified
- `menard run test --in server test/server/workline_merge_test.exs` → `{"ok":true,"tests":13,"failed":0}` (run here, on 23ff4e4).
- Server verify stage: `mise run check` exit 0 on the branch (brief, 14:55:41Z).
- The red reproduction (12/13, "untracked working tree files would be overwritten by merge: server/tmp/x") is emma's report and scharlach's — I did not re-run it, since it needs the line removed and I don't write files.

## Correctness
- `git clean -fdxq -- server/tmp` runs in `tree`, the worktree the branch is checked out in (or the throwaway one, where it is a no-op). Only `server/tmp` is touched; nothing else in `server/lib` keeps state there (every other tmp user goes through `System.tmp_dir!`), so a coworker's worktree loses only ExUnit `tmp_dir` leftovers. This very worktree has them (`server/tmp/Server.TestDatabaseNameTest/…`), so the hazard is real.
- `-x` is right: the test's second commit ignores `server/tmp/`, so `-fd` alone would leave the file. The result is discarded on purpose; a failing clean would surface as the rebase error it already was.
- The test exercises the real path: `work/finder` is checked out in `repo-wt`, so `checked_out/2` sends the rebase there, where the stray file sits.

## Non-blocking (filed as follow-up)
- The comment and pr.md say the scratch is *ignored*, but `server/tmp` is not ignored on origin/main today (`git check-ignore server/tmp/x` → 1; origin/main's `.gitignore` has no tmp line; #327 is not on main). Today's files are plain untracked. `-x` covers both cases, so no code change; the wording becomes true once #327 lands.
