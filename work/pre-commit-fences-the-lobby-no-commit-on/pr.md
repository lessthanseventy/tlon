Closes #561. A lead working a workline from its lobby seat committed on `work/t1`, so the workline read "no code" and the commits rode out with the lobby.

- `Spawn` exports `TLON_LOBBY=1` for a pane on the workspace's root machine thread, and nothing else changes.
- `scripts/git-hooks/pre-commit` refuses a commit on `work/t$TLON_THREAD` when `TLON_LOBBY` is set, and says to commit in `.worktrees/<slug>`. Uqbar's `work/uqbar-*` and a workline pane's `work/t3` still commit.
- The lead brief gains one line: commit only in the workline's worktree.

`TLON_LOBBY` is exported from `mint_and_export`, not `cwd_export`, so a lobby with no repo is marked too (and #566's change to `cwd_export` stays clear).

Checked: red first (the refusal test and the export test failed, the allowed cases passed), then green; `menard run test` on commits, spawn and profiles tests. The full gate runs on verify.
