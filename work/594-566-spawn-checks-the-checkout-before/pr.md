Spawn checks the thread's checkout before it staffs the thread, and refuses any worktree failure on a repo thread.

- `Spawn.mint_and_export` now resolves the thread and agent, runs `checkout_for` (the repo for an outside citizen, the worktree otherwise), and only then assigns. A refused spawn no longer leaves a staffed thread (or replaces the lead); a thread `env` just opened is closed.
- Only `:no_repo` exports nothing; every other `worktree_for_thread` error on a repo thread now refuses, like `:not_a_checkout` (#566).
- Catch-up stays after the assign (its lead test needs the assigned thread).

Closes #594, #566.

Checked: `menard run check --in server` — 2468 tests, 0 failed. New pins in `spawn_test.exs`: refused join leaves `agent_id` unchanged, refused env leaves no open thread, a non-`:no_repo` worktree failure is refused. Two read-dirs tests now use a real git repo as the primary.
