Closes #254 (folds in #253).

`Worktree.landed?` checked each `git cherry` "+" commit alone, so a commit later rewritten on the same branch never matched main and kept a landed branch "stranded". It now takes the union of files from all "+" commits (listed with `diff-tree -z`) and compares the branch tip against origin/main over that set. A file main changed after the landing still reads unmerged.

Checked: new test in worktree_test.exs (two commits, second rewrites the first's file, main holds the final contents) was red before the fix and is green after; `mix test test/server/worktree_test.exs` 34 tests, 0 failures.
