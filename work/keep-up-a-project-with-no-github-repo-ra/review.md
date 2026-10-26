# Review: keep-up-a-project-with-no-github-repo-ra (c25ff65)

**Verdict: request_changes.** There is one regression, and it hides a failed read from the operator.

## 1. A failed read is cleared by the next read in the same pass (blocking)

`read/3` now uses one key per repo, `"keep_up:#{repo}"`, for both reads. A pass runs them in order:

- `reland` → `read(repo, "conflicting PRs", ...)` → on `{:error, why}`: `Rollout.note(key, text)`
- `red_checks` → `read(repo, "red PRs", ...)` → on success: `Rollout.clear(key)`

Both are casts from the same process, so they apply in order and the note is gone by the end of the pass. Say `gh pr list --search conflicts` fails (rate limit, transient 502) while the `failing` read succeeds. Then the operator gets no item, and `reland` has acted on an empty PR set. That breaks the invariant the comment above `read/3` states: *"never a PR set read as empty in silence"*. It also logs the warning on every pass, because the note never survives to be seen as pending, so the log noise #613 set out to remove comes back. The reverse order does not hit this: if `conflicting` succeeds and `failing` fails, the note survives. The bug is order-dependent, which is why the three new tests miss it. Each of them fails every read or none.

**Fix:** clear the per-repo note only when every read in the pass succeeded. For example, `keep_up/2` takes both reads first, notes the first error (or clears when there is none), and passes the PR lists to `reland` and `red_checks`. Or drop the clear from `read/3` and clear in `keep_up/2` once neither read errored. Add a test: `conflicting` fails, `failing` succeeds → `notes(repo)` still has one item.

## Checked and fine

- No-origin skip: `git remote get-url origin` exits non-zero with no origin, so no gh read and no item. It is logged once per repo per node via `persistent_term`, which is written once per repo, so its GC cost doesn't matter.
- `Publish.conflicting/2`, `failing/2`, `close/4` and `follow_main/2` already take `run`, so threading it through is sound.
- The drift note uses `{:drift, repo}`, so it can't collide with the new string key.
- Commit trailers: Co-Authored-By and Tlon-Model agree (haiku-5-5).
