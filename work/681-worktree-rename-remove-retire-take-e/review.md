# Review — #681 Worktree: rename/remove/retire take ensure's lock

**Verdict: approve.** Branch `work/681-worktree-rename-remove-retire-take-e` @ aa29fc23bb96, three commits (RED test → fix → pr.md). Verify's `mise run check` exit 0 is in CHECKS; no bench_contrast row, so nothing to weigh there.

## What I checked

1. **The key cannot drift.** The witness: `locked/3` is `:global.trans({{__MODULE__, path(Path.expand(repo_path), slug)}, self()}, fun, [node()])`, byte-for-byte the key `ensure/2` used before, and `ensure`, `remove`, `retire` and `rename` are the only callers. `grep ":global" server/lib` finds two other users (`Server.Arbiter.Tmux`, `Server.Workline`): different ids, and the workline one is a `set_lock(..., 0)` try-lock, so no cross-order deadlock is possible from `Server.Workline.rename`'s call at workline.ex:150.
2. **rename/3 cannot deadlock itself.** `[first, second] = Enum.sort([from, to])`, nested. Two concurrent renames A→B and B→A take the pair in the same order. Nothing under `do_rename`/`move` calls back into a locked entry point, and `do_ensure` calls none of the other three (checked the call sites in the file).
3. **Nothing was left outside the lock.** `ensure`'s two pre-lock `cond` branches are a regex and `git_repo?`, pure of the worktree's state. `do_remove`'s `File.exists?`/`holds` check and `do_retire`'s `keep_work` are now inside the lock, where they belong. The three bodies moved verbatim, only `do_rename/5` renamed to `move/5` to free the name.
4. **The tests prove the right thing.** `blocked_while_locked` holds the exact lock id from another process, yields 300 ms, releases, and asserts the op returned only after. The rename test covers both nesting positions (held slug sorts second in `src`/`dst`, first in `src2`/`dst2`). The concurrent ensure+rename test asserts `git rev-parse --git-dir` exits 0 for every survivor, as hronir asked, not merely that nothing raised. The builder reports the blocking tests were RED unlocked; I did not re-run that.

## Notes, not blockers

- The 300 ms yield fails toward green: an unlocked op slower than 300 ms would read as "blocked". The RED run shows it was fast enough on this box; a flake, if any, would be a false pass, not a red suite.
- The `locked/3` comment (follow-up below).
