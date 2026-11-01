# Review — work/merge-queue-s-fetch-loses-the-origin-mai @ 3f740e9

**Verdict: approve.** Second round. One commit since my verdict at 5fa99c4 (`git diff 5fa99c4..3f740e9 -- . ':!work/…'`: `pr_landing.ex`, `pr_landing_test.exs`, `pr.md`). Both follow-ups from round one are done; the blocking finding is answered by a different test than the one I asked for, and I accept it (see 2).

Read: the round-two diff, `PRLanding.git/3` (L172-179), `Jobs.Land.perform` (L24-25, L154), `Merge.fetch_main`. Ran: `menard run test --in server test/server/pr_landing_test.exs` → `{"ok":true,"tests":15,"failed":0}`. CHECKS: `menard run check --in server` → 2549/0 (13:16); the server's full `mise run check` green on 3f740e9 (13:25). No `bench_contrast` row among the shown CHECKS.

## Findings

1. **Follow-up 1 fixed — a fetch still failing after the retries is interrupted.** `land/2` now wraps `fetch/2` in `interruptible/1`: `{:error, why}` → `{:error, {:interrupted, "could not fetch origin: " <> why}}`. That lands in the `else` clause that already existed for Merge's interrupted (`cut`, said only when `opts[:last]`), and `Jobs.Land.perform` L25 (`{:error, {:interrupted, why}} when attempt < max -> {:error, why}`) retries the job. `queue/5` keeps the plain error, as asked. The message now says "turn" instead of "gate", which is right since the fetch is before the gate.

2. **Round-one blocker, resolved by a different test.** I asked for lock-clears-then-lands; the builder wrote lock-never-clears → `{:error, {:interrupted, "could not fetch origin" <> _}}`, nothing posted on a non-last attempt, posted on `last: true`. It advances `origin/main` from a second clone first, so the fetch really needs the lock; the lock file is written and left, so `GitFetch.retry` runs its 3 tries through `land/2` before the error. That is the outcome the queue cares about. What it does not assert is that `retry: true` reaches `GitFetch` (the test passes with or without the retry). That is proven by read only: `fetch/2` passes `retry: true` (L145) and `git/3` branches on it (L175). Two lines; not worth a third round. Listed as a follow-up so it is not lost.

3. **pr.md nit fixed.** "full server check green (2549/0)" matches the CHECKS row.

4. **Unchanged from round one, still holds:** `GitFetch.retry/2` is a faithful lift of Merge's copy (3 tries, `250 * try` ms, only on "cannot lock ref"); `follow_main` and `Release.PM.fetch` get the retry with no outcome change; `release.sh`/`scratch.sh` call `git-fetch-origin.sh` and get its retry when #738 lands; schedule 9 left out and named open in pr.md.

Not a finding: `tlon/check: not posted — No commit found for SHA 3f740e9` in the verify row is the branch not yet on GitHub; landing re-posts on the gated sha.