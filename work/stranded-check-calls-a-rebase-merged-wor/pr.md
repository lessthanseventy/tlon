Stranded check: a rebase-merged workline's checkout is no longer called stranded.

GitHub's rebase-merge gives every commit a new SHA, and can fold a commit's files into a neighbour's diff. `Server.Worktree.unmerged?/2` used `git cherry` (patch-id) against origin/main, so #236's branch — every change already on main — read as holding unmerged commits and its checkout was reported stranded.

A commit now counts as landed when the files it touched are identical on origin/main (`landed?/3`). A commit whose files differ there still holds the checkout.

Tests (`server/test/server/worktree_test.exs`, `stranded/2`):
- red first: a rebase-merged branch reported `work/landed has unmerged commits`
- guard: a branch whose change differs on origin/main is still named

Ticket #215.

Checked: `server/` full suite, 1596 tests, 0 failures (`menard run test --in server`).
