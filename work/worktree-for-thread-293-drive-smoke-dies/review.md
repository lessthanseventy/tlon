# Review — worktree-for-thread-293-drive-smoke-dies

No free reviewer at the builder's grade (senior): this review was done by ulrikke, a reviewer below that grade, so weigh the verdict accordingly.

**Verdict: approve.** Branch `work/worktree-for-thread-293-drive-smoke-dies`, commits 356cd99, b5edbf9, 5b7ec5e, against main.

## What I checked
- Read the diff of `server/lib/server/worktree.ex`, `server/test/server/worktree_test.exs` and `pr.md`.
- The lock form is right: `:global.trans({{__MODULE__, path}, self()}, fun)` keys on the checkout path; the requester is the calling process, so concurrent callers serialise.
- `path/2` is the same path `do_ensure/2` uses, so the lock and the checkout agree.
- `resolve/2` re-checks `git rev-parse --git-dir` after `add` and on an existing-checkout hit, repairs once, and returns an error if the repair still fails instead of a silent `{:ok, wt}`.
- Both new tests exercise the reported failures: 8 concurrent ensures, and a gitfile with a stray `1`.
- I did NOT run the tests myself. The verdict rests on the server's record that `mise run check` passed on 5b7ec5e, plus my reading of the diff.

## Non-blocking (also in follow_ups)
- The `:global` lock covers only `Server.Worktree.ensure` in this BEAM node. Other `git worktree add` callers on the same path (scripts, `scratch:new`) can still race.
- The lock comment and the `describe` label cite `#447`. AGENTS.md says comments carry the why, not ticket refs; trim on a later touch.
- `seed_deps` now runs while the lock is held, so concurrent ensures of one slug wait for the copy. Fine for now; revisit if the copy gets slow.