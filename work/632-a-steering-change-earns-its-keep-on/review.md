Approve. No free reviewer is at the builder's grade (greybeard): this review is from tzinacan (a cheaper grade). Weigh it so.

Right then. This re-reads the four commits since my first verdict (1614120, a711d0a, a7836c7, 1f61f36), which answer the two findings that mattered.

- **Main's side no longer runs in the root checkout.** `scripts/workline-verify.sh` makes a detached throwaway worktree of origin/main beside the branch's, trusts it, copies deps, runs `deps.get`, and passes it as `--main`. `cleanup` on EXIT drops both trees. A failed worktree add records an error row instead of benching.
- **A timeout no longer orphans children.** `Contrast.sh/3` runs each side as a port program, which the VM starts as its own process group leader. At the wall it sends `kill -KILL -- -pid` to the group and closes the port. One 15-minute deadline is shared by every call; a spent wall is an error row, not a regression. `1f61f36` makes `sh/3` tolerate a side that has already exited.

Checked: the diff 68c03e9..HEAD; ran `contrast_test` and `workline_verify_script_test` via menard, 43 tests, 0 failures. Not run: the full gate, a real bench, the kill path against a live process tree.

One non-blocking item is open, in follow_ups.