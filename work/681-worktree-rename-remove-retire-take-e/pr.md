# Worktree: rename/remove/retire take ensure's lock

`Server.Worktree.ensure/2` serialised on `:global.trans` keyed on the expanded repo path + slug, but `rename/3`, `remove/2` and `retire/2` took no lock, so one running beside an ensure of the same slug could leave a gitfile pointing nowhere.

All four now go through one `locked/3` (same key, so it can't drift); `rename/3` takes `from` and `to` in sorted order, nested (same-process re-entry, fixed order, no deadlock).

Closes #681.

Checked: new tests hold the lock from another process and assert each of the three blocks (RED before the change: not blocked), plus ensure + rename of one slug concurrently with every survivor's `git rev-parse --git-dir` exiting 0. `menard run test` on worktree_test.exs 61/61; `menard run check --in server` 2544 tests, 0 failed.
