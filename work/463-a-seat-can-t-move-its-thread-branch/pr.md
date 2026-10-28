# A seat can't move its thread branch onto main: the service does it (#463)

A coworker's sandbox bind-mounts `.claude/settings.json`, which is tracked, so any `git rebase` or
`git reset` onto origin/main in its own Bash dies half-way ("unable to unlink", "Entry not uptodate"),
leaving hundreds of files rewritten under a stuck HEAD. The move has to run on the server.

What changed:
- `Server.Worktree.bring_to_main/1`: `catch_up/1`'s fast-forward for a clean branch behind main, a
  `rebase --no-update-refs origin/main` for one with commits of its own, and a refusal with the reason
  for a dirty tree, a half-done rebase/merge/cherry-pick, a detached HEAD, or a conflict (the rebase
  aborted, the branch exactly as it was). Never fetches: it trusts the refs KeepUp keeps fresh.
- `Server.bring_branch_to_main/1`: the facade for a thread, every outcome posted as a tlon notice.
- The `catch_up_branch` MCP tool: the seat's own thread, or one it leads by `thread_id`, like
  `push_branch`. A refusal is the tool's error with the reason.
- The builder brief and root AGENTS.md name it beside `push_branch`.

Closes #463. Out of scope: #655 (the sheriff seat's scratch dir).

How it was checked: eight `bring_to_main/1` cases, the facade's three notices and the tool's listing,
non-lead refusal and a real move-then-refuse call, each red before its code; then
`menard run check --in server`: 2366 tests, 0 failures.
