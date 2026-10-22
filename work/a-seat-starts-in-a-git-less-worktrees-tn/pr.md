# A spawn refuses a worktree dir that is not a checkout (#563)

`Worktree.ensure` met a plain `.worktrees/<name>` dir with no `.git` (a stray `work/…` written after
a promotion moved the checkout), git refused to add into it, and `Spawn` quietly dropped `TLON_CWD`:
the seat started elsewhere and its git fell up to the live main checkout.

Now `ensure` returns `{:error, {:not_a_checkout, path}}` for that dir and `Spawn.join/env` refuses
with it. The stale dir is left alone (`.worktrees/t326` is a live seat's cwd; removing it is the operator's call).

Checked: red test in `test/server/mcp/spawn_test.exs` failed (spawn returned `:ok` with no cwd), green
after; `menard run test` in server: 1988 tests, 0 failures.
