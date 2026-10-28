push_branch: prune the branch's tracking ref before leasing

A landing deletes `work/<slug>` on origin but leaves the shared repo's `origin/work/<slug>` at the old
head, so the next `push_branch` was refused with "stale info" (seen on #144). `Publish.push_branch/3`
now runs `git fetch --prune origin +refs/heads/<branch>*:refs/remotes/origin/<branch>*` first, so a
deleted branch is leased as absent. A glob refspec is deliberate: git's explicit refspec dies
"couldn't find remote ref" on a deleted branch and prunes nothing (checked against a bare repo). A
failed fetch refuses the push with its output.

Closes ticket #469.

Checked: `workline_publish_test.exs` 26/26 (two new tests: prune-fetch runs and precedes the push;
a failed fetch pushes nothing). The pruning itself was verified by hand against a real bare repo.
