# Review — seat-bash-overflow-find-what-the-session (#329)

**Verdict: request_changes.** One finding blocks. The rest of the diff is sound.

## 1. BLOCKING: the green verify tested a tree that HEAD does not contain
The verify check at 23:32:49 reads: "tlon/check: not posted — the tree has uncommitted or untracked changes". The worktree has this uncommitted change in `office/test/cast-view.test.ts`:

```
   keys("C-]")
+  await until("home", () => !screen().includes("THE CAST"))
```

It appears twice: at the end of "the cast opened again after ctrl+] still lists the bench" and at the end of the soul test. This is the flake fix from fact #3153. HEAD `3faf359` only has the `until()` once-per-read change, so the persona test can still get its keystroke on a stale cast. The 804-pass run vouches for the dirty tree, not for the branch.
**Fix:** commit those two lines as their own commit (the flake: the preceding test leaves the cast open). Then run verify again on a clean tree so `tlon/check` posts on that sha.

## Verified, not blocking
- `scripts/bwrap-argc.sh`: the total is the NUL count, which is right because cmdline ends every arg with a NUL. The test's 15 matches by hand count. On my own seat it printed `total 802`, with `138 /home/andrew/projects/tlon/.git/worktrees` and `32 /dev/null`. The only mount options in my argv are `--ro-bind`, `--bind` and `--tmpfs` (counted with `uniq -c` over `/proc/1/cmdline`), so the awk's option set covers everything this harness emits.
- The `/worktrees/` cut `substr(p, 1, index+9)` gives `/x/.git/worktrees`, as the test asserts.
- `office/test/until.ts` fixes the double read: the old code ran `while(!ok())…; if(!ok()) throw`, which is how the error "never saw the cast after 45ms" happened. `until.test.ts` goes red on the old shape (reads `[false,true,false]`).
- It is wired into `check:names` and stays offline and fast.

## Scope (design, not code; for the tech lead)
The goal reads "find what the session adds … **then bound it**". This branch ships the instrument and a flake fix. The cause is still a hypothesis (ireneo: a cwd=$HOME scan, or the profiles_test repos under server/tmp #558), and nothing is bounded. If this merges as-is and finish closes #522, the overflow ships unfixed with its ticket closed.
