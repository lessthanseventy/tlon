# Share the lost-ref-lock fetch retry (#645)

`Workline.Merge.fetch_main` already retried a fetch that lost `refs/remotes/origin/main`'s lock to a concurrent fetch; the other fetches in the shared `.git` did not.

- `Server.GitFetch.retry/2`: the one retry (3 tries, backoff, only on "cannot lock ref"); Merge's private copy is gone.
- `PRLanding.fetch`, `Publish.fetch_and_follow` (follow_main) and `Release.PM.fetch` use it. In `land/2` a fetch that still fails after the retries is `{:interrupted, "could not fetch origin: …"}`, so the queue retries the turn instead of consuming it.
- `release.sh` and `scratch.sh` fetch through `scripts/git-fetch-origin.sh`. The retry in that script is #738's; they get it when #738 lands.

**Still open:** schedule 9 (nightly role bench) runs a bare `git fetch -q origin` from its database row. It needs a PATCH from someone with host access, after #738 is on main. This PR does not close that exposure.

Checked: `menard run test --in server` on git_fetch (new), workline_merge, pr_landing, release_script; full server check green (2549/0).
