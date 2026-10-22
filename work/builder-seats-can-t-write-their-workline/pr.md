# A sandboxed seat may write its worktree and its gitdirs

Closes #497.

The profile's `allowWrite` (`Server.Profiles`) is compiled in: in the service, its "tlon checkout"
entry resolves to `tlon/.release`, so a seat's only write root in its workline was its cwd (`.`).
A linked worktree's commit writes its gitdir (`.git/worktrees/<slug>`) and the common `.git`, which
sit outside the worktree, so a seat could edit but not commit. `adapters/claude-code/launch.sh` now
adds `$PWD`, `git rev-parse --absolute-git-dir` and `--git-common-dir` to the sandbox's allowWrite
(deduped, the profile's entries first). `_build` sits inside the worktree, so it rides on `$PWD`.

Still open, not in this change: a pane that boots without `TLON_CWD` starts outside its worktree
(emma's seat on #340, cwd `/run/user/1000`) — that is #566.

Checked: a new test in `adapters/claude-code/lib/launch.test.ts` dry-runs the launcher from a linked
worktree and asserts allowWrite lists the worktree and both gitdirs; it went red (the three paths
missing) before the fix and green after. `mise run adapters:claude-code:check`: 86 pass, 0 fail.
