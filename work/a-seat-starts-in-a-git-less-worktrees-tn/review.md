# APPROVE — a-seat-starts-in-a-git-less-worktrees-tn

Verdict: **approve**. The #563 fix (e353685) is unchanged from the a6bb510 I approved last round — byte-identical on `spawn.ex`, `worktree.ex` and `spawn_test.exs`. The only change since 019ea48 is dropping the two redundant #562 office commits (aef3025, ae862ad), now on origin/main as 9749a44/dcb4452. `mise run check` is green on e50d577.

## The fix, re-affirmed

`Worktree.add` tags `{:not_a_checkout, wt}` when `git worktree add` refuses and the dir exists with no `.git`. `cwd_export` propagates that as `{:error, refused}` and returns `{:ok, ""}` for other errors (unchanged behavior). `mint_and_export`'s `with` short-circuits on the refusal before `Tokens.mint`, so `Spawn.join/env` refuse loud instead of dropping `TLON_CWD` and the pane starting somewhere else. The red-green test in `spawn_test.exs` covers the `join` path. Sound, surgical; `cwd_export` has the one caller, so the return-type change is safe.

## No conflict with origin/main

origin/main advanced ~30 commits past this branch's base (69fe9b5), including `9bad5e0 boot: a seat starts in its worktree or not at all` (#522, in `tmux.ex`). That is a different layer — the boot line's own refusal of a gone / no-`.git` cwd — and touches no file e353685 does. They compose: e353685 refuses at spawn (the MCP call errors before the pane boots), 9bad5e0 is the boot-line safety net for an empty or gone `TLON_CWD`. Neither subsumes the other. origin/main did not touch `spawn.ex` or `worktree.ex` in the gap (the net diff vs origin/main is exactly e353685's footprint), so the landing rebase will apply clean.

## Follow-ups (non-blocking, carried from the first review)

1. **Refusal leaks a staffed thread** — `ensure` (opens the thread, registers/assigns the agent) runs before `cwd_export` refuses, so a `not_a_checkout` refusal leaves a staffed thread behind. The reorder is out of scope for this change; the ticket is filed once this workline merges, with a regression pin asserting the thread's agent after a refused `Spawn.join`.
2. **Other `Worktree.ensure` errors still drop `TLON_CWD` silently** — `not_a_repo` / generic git refusal return `{:ok, ""}` from `cwd_export`, so the pane starts in tmux's default dir. Filed as #566.