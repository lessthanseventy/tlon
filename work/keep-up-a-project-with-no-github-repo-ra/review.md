# Review: keep-up-a-project-with-no-github-repo-ra (f5cb619)

**Verdict: approve.** The blocking finding from the last review is fixed, and it is proven by a test that goes red against the old code.

## 1. A failed read is no longer cleared by the other read's success (was blocking) — fixed

`keep_up/2` now takes both reads before anything is cleared (`server/lib/server/jobs/keep_up.ex:38-41`): `conflicting` and `failing` are read first, `Rollout.clear/1` runs only when neither is `:error`, and `unread/1` (`:240-241`) feeds `[]` to `reland/3` and `red_checks/3` so an errored read is acted on as nothing. I walked the four combinations:

- conflicting fails, red succeeds (the reported bug): `read/3` notes, nothing clears, the note survives the pass.
- red fails, conflicting succeeds: same, note survives.
- both succeed: cleared once.
- both fail: one keyed note (the second reason overwrites the first), never cleared.

`read/3`'s behaviour is otherwise unchanged, including "log only when no note with that key is pending".

Both reads bottom out in `open_prs/3` (`server/lib/server/workline/publish.ex:98-109`), which returns `{:ok, list}` or `{:error, why}` and never `:skipped`, so `read/3`'s `{:error, why}` clause covers every failure shape and nothing falls through to the list clause.

The new test (`server/test/server/jobs/keep_up_test.exs:267-282`) is the right shape: the `mergeStateStatus` read fails, the `statusCheckRollup` read returns `[]`. Against the old `read/3` (clear on any successful read) the note would be gone and `notes("/r/half")` empty, so it is red first.

Verified here: `menard run test --in server test/server/jobs/keep_up_test.exs` → 19 tests, 0 failed. The verify stage's `mise run check` on f5cb619 is green (server 2073, 0 failed).

## 2. The earlier follow-up is still fixed (checked)

`github_remote?/2` (`keep_up.ex:51-57`) still requires origin's host to be github.com in https/ssh/scp form; GitLab and bare paths are skipped with no gh read and no item.

## Checked and fine

- No-origin skip, the once-per-repo log line, and one note per unresolvable repo (not two) all still hold; the tests at `keep_up_test.exs:236-262` cover them.
- Threading `run` through the two reads and making `keep_up/2` public with a stub default leaves the existing per-function tests calling the stubs they already use.
- Trailers name the authors that wrote the commits (bf11678 sonnet-5-5 era work, f5cb619 pr.md).

## Follow-ups (non-blocking, still open)

1. `github_remote?` misses credentialed and `git://` remotes
   A remote like `https://x-access-token:…@github.com/org/repo` or `git://github.com/…` does not match, so such a repo is skipped silently. No remote on this box is in that shape today; if it matters, cover the userinfo: `~r{^(?:(?:https?|git|ssh)://)?(?:[^@/]+@)?github\.com[/:]}`.

2. A repo that loses its GitHub origin keeps a pending note
   The skip path clears nothing, so a `keep_up:` note raised before the origin changed stays until dismissed — one dismissible item.

3. `red_checks/2` clears on half a pass
   `keep_up.ex:154-156` clears `keep_up:#{repo}` when the red-PRs read alone succeeds. That is correct for the standalone call its tests make (the "note clears once it reads" test asserts it), but it is now the only clear in the module not guarded by both reads: a caller running `red_checks/2` inside a pass would re-wipe a conflicting-PRs note. One line saying the pass owns clearing, or moving the clear to the caller, closes the trap.