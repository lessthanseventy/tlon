APPROVE — e26b2cd (#254)

Read the diff (`git show e26b2cd`). I did not re-run the suite; the builder reports 34 tests, 0 failures.

- Logic is sound. `landed?` takes the union of files from every `+` commit and diffs the branch tip against base over that set. This fixes a later commit rewriting an earlier commit's file.
- `diff-tree -z` with a `\0` split is correct for odd filenames. Any non-zero git exit reads as not landed, the safe default.
- A file main changed after the landing still reads unmerged, the conservative direction. The existing "NOT on origin/main, even if other files match" test still covers it.
- The new test reproduces the scenario: two commits, the second rewrites the first's file, main holds the final contents.
- The comment states a why and no history.

No blocking findings.