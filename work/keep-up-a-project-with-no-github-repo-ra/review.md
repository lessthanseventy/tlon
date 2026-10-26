# Review: keep-up-a-project-with-no-github-repo-ra (4ff660f)

**Verdict: request_changes.** The previous review's blocking finding is unchanged; only its follow-up was fixed.

## 1. A failed read is still cleared by the other read's success (blocking, carried from the last review)

`read/3` still uses one key per repo (`keep_up:#{repo}`) and clears it on any successful read (`server/lib/server/jobs/keep_up.ex:98-101`). A pass reads `conflicting PRs` first and `red PRs` second (`keep_up.ex:37-43`), and `Rollout.note/2` and `Rollout.clear/1` are casts from the same process, so they apply in order. When the conflicting read fails and the failing read succeeds:

1. `read(repo, "conflicting PRs", {:error, why})` → `Rollout.note("keep_up:#{repo}", "can't read conflicting PRs…")`, and logs the warning because no note with that key is pending.
2. `read(repo, "red PRs", [])` → `Rollout.clear("keep_up:#{repo}")`.

The note is gone by the end of the pass: the operator gets no item, `reland/2` has acted on an empty PR set, and that is exactly the invariant `read/3`'s own comment states ("never a PR set read as empty in silence"). The warning also logs on every pass, since the note never survives to be pending — the log noise #613 set out to remove. The three tests from c25ff65 each fail every read or none, and 4ff660f's test never gets past `github_remote?`, so nothing covers it. The reverse order does not hit it (conflicting succeeds → clear, failing fails → note survives); the bug is order-dependent.

**Fix:** clear the per-repo key only when every read in the pass succeeded. For example: `read/3` returns `{:ok, prs}` or `{:error, text}`; `keep_up/2` runs both reads, calls `Rollout.clear("keep_up:#{repo}")` only when neither is an error, and gives the lists to `reland`/`red_checks` (a private `red_checks/3` taking the list, keeping `red_checks/2` with its own read for the tests that call it directly).

**Test that must be red first:** a `run` that fails the `gh pr list` call whose `--json` contains `mergeStateStatus` and returns `"[]"` for the one containing `statusCheckRollup`; assert `notes(repo)` still holds one item after `KeepUp.keep_up/2` (with a `pass/2`-style origin returning a github.com URL).

## 2. The last review's follow-up is fixed (checked)

`github_remote?/2` (`keep_up.ex:53-58`) now requires the origin's host to be github.com, matching `git@github.com:…`, `https://github.com/…` (with or without `.git`) and `ssh://git@github.com/…`; `https://codeberg.org/…` and bare paths return false. The new test covers the GitLab and bare-path cases, and it does prove no note is raised (a true `github_remote?` would hit the gh error stub and file one).

## Checked and fine

- No-origin skip: `git remote get-url origin` exits non-zero, so no gh read and no item; the log line is once per repo per node via `persistent_term`.
- One note per repo for a repo GitHub can't resolve (the `a11y-with-phoenix-guide` case) — the two reads collapse to one item, which is what the ticket asks.
- Threading `run` through `Publish.conflicting/2`, `failing/2`, `close/4`, `follow_main/2` and making `keep_up/2` public with a default stub is sound; the existing tests still call the stubs they use.
- Trailers agree with the authors (4ff660f sonnet-5-5, c25ff65 haiku-5-5).

## Non-blocking, not filed

- `github_remote?` would not match a remote carrying credentials (`https://x-access-token:…@github.com/org/repo`) or `git://github.com/…`, so such a repo would be skipped silently. No remote on this box is in that shape today (checked every project's `.git/config`); if that matters, cover the userinfo: `~r{^(?:https?://|ssh://)?(?:[^@/]+@)?github\.com[/:]}`.
- A repo that loses its GitHub origin while a `keep_up:` note is pending keeps that stale note, since the skip path clears nothing — one dismissible item.
