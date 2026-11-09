A workline in a repo with its own `core.hooksPath` now staffs, and a lead whose spawn is refused says so on its thread.

Why #550 never launched: `Worktree.ensure` refused any repo that has its own `core.hooksPath` (ficciones: `scripts/git-hooks`), and `Switchboard.maybe_spawn_absent` filtered `Spawn.join/3`'s `{:error, _}` out of its comprehension, so the refusal left nothing but the 1h stall alert.

- `Worktree`: such a repo keeps its hooks in its main checkout; its seat worktree alone is pointed at tlon's (`extensions.worktreeConfig` + `git config --worktree core.hooksPath`), so the fence and the `Tlon-Model` stamp still apply. Chaining the repo's own hooks is not done here.
- `Switchboard.join_exports/3`: a lead's refused join posts the same "could not be seated … <reason>" notice a refused pane spawn does.

Closes ticket #864 (workline #550).

Checked: `menard run test` on worktree, switchboard and spawn tests (158, 0 failures); both new behaviours red first; credo clean.
