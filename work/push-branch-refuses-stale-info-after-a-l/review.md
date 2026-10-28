# Review: push_branch prunes the branch's tracking ref before leasing (#469)

**Verdict: approve.** Branch `work/push-branch-refuses-stale-info-after-a-l` @ 1e4aa50e736d, one commit over main 3b98690.

## What it does
`Publish.push_branch/3` now runs `git fetch --prune origin +refs/heads/<branch>*:refs/remotes/origin/<branch>*` before `git push --force-with-lease origin <branch>`. A branch a landing deleted is leased as absent; a failed fetch refuses the push with its output. The name check moved to `thread_branch/1`, the push to `lease_push/3`; behaviour unchanged there.

## Verified (by me, real git 2.56, scratch bare repo, no push)
1. Explicit refspec on a deleted remote branch: `fatal: couldn't find remote ref work/tiles`, tracking ref untouched. The code comment is exact.
2. Glob refspec with `--prune`: `- [deleted] (none) -> origin/work/tiles`, exit 0. Nothing matching the glob on the remote at all: still exit 0 and the stale ref is pruned. So the lease then expects "absent", which is the ticket's fix.
3. Branch charset `work/[a-z0-9][a-z0-9-]*` has no glob character; `own_branch`'s named branches pass the same regex, so the refspec can't be shaped by a caller.
4. Server's verify: `mise run check` exit 0 on the branch (CHECKS 2026-10-28T23:13:26Z). No bench_contrast row.

## Findings
- **Design note, accepted:** fetching the tracking ref immediately before `--force-with-lease` makes the lease pass against whatever origin holds at that instant, so a landing's rebased copy is overwritten by the seat's push. That is what ticket #469 asks for; the only other pusher of `work/<slug>` is the server's own landing, and the merged PR is already closed.
- **Side effect, harmless:** the glob also refreshes and prunes sibling tracking refs (`work/tiles-2`, `work/tilesx`) in the shared repo, toward origin's truth.
- **Non-blocking (follow-up):** `Publish.fetch_branch/3` is now subsumed by `prune_branch/3`; `Workline.merge_again/5` calls `fetch_branch` then `push_branch`, two fetches on the re-landing path.
- **Nit:** the "prunes before leasing" test asserts both calls ran and differ, not their order; the failed-fetch test pins the order in practice.

## Spec compliance
Ticket-born workline, no spec.md/plan.md. The ticket's stated fix ("push_branch runs `git fetch --prune origin work/<slug>` before taking its lease") is implemented, with the refspec corrected to the form git actually prunes with. pr.md says what changed, why, the ticket, and how it was checked.