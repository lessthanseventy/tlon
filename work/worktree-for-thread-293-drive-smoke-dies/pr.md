Serialise `Server.Worktree.ensure` per path and repair a gitfile that names a missing gitdir.

Two concurrent `git worktree add`s on one path made the loser take `<name>1`, overwrite the winner's
`.git` file with it, fail, and delete its admin dir — leaving a checkout whose gitfile points nowhere
("gitfile does not point to a valid repository"; stalled review of 293, red verify on 393/#420).
`ensure` now runs under a `:global.trans` lock keyed on the checkout path, and after an add (or for an
existing checkout) verifies `git rev-parse --git-dir`, running `git worktree repair` when it fails.

Closes ticket #447 (and #436, issue #40).

Checked: two new tests in `worktree_test.exs` (8 concurrent ensures; a corrupted `…1` gitfile) went red
first, now green; `mix test test/server/worktree_test.exs` 36 passed.
