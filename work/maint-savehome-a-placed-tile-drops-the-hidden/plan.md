# Plan — land the saveHome fix (#281)

No new code. The fix is on `work/savehome-a-placed-tile-drops-the-hidden` (head c732fa4). Run all from a scratch worktree (`mise run scratch:new -- savehome-land origin/main`), never the live checkout.

## Task 1 — rebase and re-test
- `git fetch origin && git rebase origin/main work/savehome-a-placed-tile-drops-the-hidden` in the scratch worktree (a rebase of the branch, not a merge).
- Verify: `cd office && bun test test/home.test.ts` — expect 29 pass, 0 fail (via `scripts/cap.sh`).
- Done: rebase clean (no conflicts in `office/tui/home.ts`, `office/test/home.test.ts`) and tests green. On conflict, stop and post it on the thread.

## Task 2 — decide whether the approval is still valid
- Land requires the newest review on the branch to approve its head, or that head rebased onto main with the same patches.
- Compare: `git range-diff c732fa4~N..c732fa4 origin/main..HEAD` (or `git patch-id` per commit). Same patches → approval stands, go to Task 3.
- Patches differ → `review_branch` for one fresh round (reviewer not the builder), wait for approve.
- Done: an approving review exists for the exact head to land.

## Task 3 — land
- Push the branch to origin (`push_branch`), open a PR if none exists (`gh pr list --head work/savehome-a-placed-tile-drops-the-hidden`).
- `mise run land -- <pr>` (service must be up; the gate runs in the queue, don't call `check:all`).
- Done: `git fetch origin && git log origin/main --oneline | grep -i saveHome` shows the fix; PR state MERGED (a "closed" notice alone is not proof).

## Task 4 — close
- `cd office && bun test test/home.test.ts` on updated origin/main passes.
- `finish(summary)` on thread 289; close #281's workline.
- Done: threads 289 and 281 closed.
