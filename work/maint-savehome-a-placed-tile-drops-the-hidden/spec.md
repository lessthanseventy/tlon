# Spec — unstick workline savehome-a-placed-tile-drops-the-hidden (#281)

## Finding
The code change is already built and approved; the workline only stalled at `review`.
Branch `work/savehome-a-placed-tile-drops-the-hidden` (head c732fa4) holds:
- `office/tui/home.ts` `saveHome`: a placed known tile wins its cell; a hidden unknown-kind tile on that cell is dropped; a hidden tile with a non-array `at` is kept (no throw).
- `office/test/home.test.ts`: two tests (collision dropped; malformed `at` carried).
- Round-3 review verdict: approve; `bun test` 29/29, `mise run check` exit 0, QA re-drove on a scratch release.

## Requirements
1. No new code. Do not rebuild or re-review.
2. Land the existing branch through the merge queue: `mise run land -- <pr>` (its newest review approves its head), or the workline's own approval if it is still live.

## Plan (maintainer)
1. Confirm head c732fa4 is still approved and rebases cleanly onto origin/main (`git rebase origin/main` in a scratch worktree; re-run `bun test office/test/home.test.ts`).
2. If clean: land it. If the review is stale after a rebase: one fresh review round on the rebased head, then land.
3. Close #281 and this thread with `finish`.

## Done when
`git log origin/main` contains the saveHome fix and `office/test/home.test.ts` passes on main.
