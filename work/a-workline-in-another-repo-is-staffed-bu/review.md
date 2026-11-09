# Review: a workline in another repo is staffed but its lead never launches

**Verdict: approve.** Branch `work/a-workline-in-another-repo-is-staffed-bu` @ 3cc8a45 (2 commits, +86/−9).

The witness statement: `Worktree.ensure` refused any sibling repo with its own `core.hooksPath` (ficciones has one), and `maybe_spawn_absent`'s comprehension silently filtered `Spawn.join`'s `{:error, _}`. Both named in pr.md, both fixed, both tested.

## What I verified

1. `menard run test test/server/worktree_test.exs test/server/switchboard_test.exs` → `{"ok":true,"tests":131,"failed":0}`.
2. `join_exports/3` only speaks for the thread's lead (`agent.id == thread.agent_id`) and reuses `note_unseated/3`, so the drain's minute retry dedupes on the same `said` prefix as a refused pane. Correct.
3. `do_ensure`'s guard: `hooks == :ok or elem(hooks, 0) == :own` short-circuits for `:ok`, and `{:error, _}` falls out of the `with` unchanged. Correct, if ugly (see follow-up 2).
4. `scope_hooks/3` is idempotent: the worktree test loops `ensure` twice and the shared `core.hooksPath` stays `elsewhere`.
5. ficciones' own `scripts/git-hooks/pre-commit` already fences on `TLON_THREAD`; it also runs a manual-gen check. Tlon's hooks replace it in the seat worktree, so that check is skipped there. Its own comment says `mise run check` catches the drift, so not blocking.
6. Verify's CHECKS rows: full gate green (2815 passed) in a train with #554. No `bench_contrast` row, nothing graded.

## Not verified by me

The pr.md's "red first" and "credo clean" claims. I did not check out main to see the tests fail.

## Findings (non-blocking, as follow-ups)

See follow-ups.
