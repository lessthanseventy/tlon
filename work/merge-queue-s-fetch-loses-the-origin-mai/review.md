# Review — work/merge-queue-s-fetch-loses-the-origin-mai @ 1594fde

**Verdict: request_changes.** The code is right; one owed test is missing. The scope note (scharlach, msg 27623, point 2) asked to "test the ones where a lost lock changes the outcome", and the builder said in msg 27647 that only Merge has one. PRLanding is exactly such a one, and nothing but a read proves its `retry: true` is threaded. A cheap send-back beats a ticket here.

Read: the full diff (2 commits, 10 files), `Server.GitFetch`, each call site's failure path, `Jobs.Land.perform`, `KeepUp.keep_up`, `scripts/scratch.test.sh`, `scripts/git-fetch-origin.sh`. Evidence I lean on but did not run: CHECKS rows `menard run check --in server` → `{"ok":true,"tests":2548,"failed":0}` (12:53) and the server's full `mise run check` green (13:03). No `bench_contrast` row in CHECKS.

## Findings

1. **Blocking — no lost-lock test for `PRLanding.land/2`.** Before this branch a lost lock in `land/2`'s fetch ended in `✗ not landed`; now it lands. That is the one call site where the outcome changes, and it goes through a new `opts[:retry]` branch in a private `git/3`. `pr_landing_test.exs` has the fixture for it (a real clone with a bare origin). Copy `workline_merge_test.exs`'s pattern: advance `origin/main` from a second clone (the fixture's clone is already level, so a fetch would not need the lock), write `.git/refs/remotes/origin/main.lock`, `spawn` its removal after ~400 ms, `approve(ctx, origin(ctx, "feature"))`, then `assert {:ok, _} = land(ctx)` and `assert posts(ctx) =~ "✓ merged"`.

2. **Verified, not a finding — what each site does on a fetch that still fails after 3 tries** (the scope note's question, answered since the builder didn't):
   - `Merge.fetch_main`: `{:interrupted, …}` → Jobs.Land retries the job. Unchanged, 3 tests.
   - `PRLanding.land`: `{:error, "git fetch failed: …"}` → `✗ not landed` posted and `Jobs.Land.perform` returns `:ok`: the landing is consumed, not retried. `PRLanding.queue`: the error goes back to the caller of `land_pr`, who can retry. See follow-up.
   - `Publish.follow_main`: `{:error, …}` → `KeepUp.drifted/2`; the next pass is 5 min later. No outcome change beyond fewer false drift notes.
   - `Release.PM.fetch`: its result is ignored at all three callers (`status`, `check`, `propose`); the retry only raises the odds `origin/main` is fresh. No outcome change.

3. **`GitFetch.retry/2` is a faithful lift of Merge's copy.** Same 3 tries, `250 * try` ms, only on `"cannot lock ref"`, last answer stands. `{out, code} = failed when code != 0 and try < @tries` returns the third failure through the `done` clause as intended; the three unit tests cover success-after-retry, bounded tries, and a non-lock failure not retried.

4. **Scripts.** `release.sh` has `$root` defined (line 24) before the three uses; passing `"$root"` to the script is at least as correct as the cwd-relative fetch it replaces. `scratch.sh` uses `$(dirname "$0")`, and `scratch.test.sh` runs it in place (`"$here/scratch.sh"`), so the sibling resolves; the names gate passed. `release_script_test` copies `git-fetch-origin.sh` beside `release.sh` in its temp repo. As the pr.md says, these get no retry until #738 lands; the script untouched here, per scope.

5. **Nit, pr.md:** "full `menard run check --in server` below" points at nothing in the file; the server appends CHECKS itself. Drop "below".

Not findings: `tlon/check: not posted — No commit found for SHA 1594fde` in the verify row is the branch not yet on GitHub; landing re-posts on the gated sha. Schedule 9 correctly left out and named open.