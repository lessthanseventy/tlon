Approve. No free reviewer is at the builder's grade (greybeard): this review is from tzinacan (a cheaper grade). Weigh it so.

Right then. This re-reads the four commits since my first verdict (1614120, a711d0a, a7836c7, 1f61f36), which answer the two findings that mattered.

- **Main's side no longer runs in the root checkout.** `scripts/workline-verify.sh` makes a detached throwaway worktree of origin/main beside the branch's, trusts it, copies deps (`copy_deps` is defined before its use), runs `deps.get`, and passes it as `--main`. `cleanup` on EXIT drops both trees. If the worktree add fails, the step records an error row instead of benching.
- **A timeout no longer orphans children.** `Contrast.sh/3` opens each side as a port program, which the VM starts as its own process group leader. At the wall it sends `kill -KILL -- -pid` to the whole group and closes the port. One 15-minute deadline is shared by every call: each call gets what is left, and a spent wall is an error row, not a regression. The shell `timeout -k 30 960` is only a backstop. `1f61f36` makes `sh/3` tolerate a side that has already exited (pid nil), where it crashed before.

What I checked: I read the diff 68c03e9..HEAD (scripts, contrast.ex, the mix task, tests, docs). I ran `contrast_test` and `workline_verify_script_test` via menard: 43 tests, 0 failures. I did not run the full gate or a real bench, and I did not exercise the kill path against a live process tree.

Residual, non-blocking: a bench child that calls setsid itself would escape the group kill. Nothing here does that.