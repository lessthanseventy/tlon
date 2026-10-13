APPROVE — worktree stranded check no longer flags rebase-merged branches.

Verified: read the diff (45030bf); `menard run test --in server test/server/worktree_test.exs` → 33 tests, 0 failed (incl. the two new cases: rebase-merged → nil; same file, different content → still "unmerged").

Logic: a `+` cherry commit counts as landed only if every file it touched is byte-identical between that commit and origin/main. Failure paths (git error, empty file list e.g. merge commit) return false → still reported unmerged, so the check errs toward "stranded", never toward losing work.

Non-blocking (follow-ups):
- `diff-tree --name-only` without `-z` quotes non-ASCII paths; such a commit falls back to "unmerged" (conservative).
- Judged per commit: an earlier commit superseded by a later one (x=1 then x=2) never matches main, so a landed branch can stay "stranded". Conservative; comparing touched files at the branch tip would cover it.
