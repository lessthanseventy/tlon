# Merge queue: retry a fetch that loses the origin/main ref lock (#645)

Closes #645.

The requeued landings and KeepUp all fetch origin in the one shared `.git` at once; the fetch that
loses the race fails with `cannot lock ref 'refs/remotes/origin/main'` although the ref is fine, and
the landing bounced the workline back to build for it.

## What changed

`Server.Workline.Merge`: the `fetch origin main` in `merge/3` and `stack/3` now goes through one
`fetch_main/1`. A fetch that fails with `cannot lock ref` is tried again, up to 3 tries, 250ms then
500ms apart; once the winning fetch is done it succeeds as a no-op and the landing proceeds.

A fetch that still fails returns `{:error, {:interrupted, "could not fetch origin …"}}` instead of a
plain `{:error, why}`. That is the shape a gate killed mid-run already returns, so every caller rides
the retry that exists: `land_queued/2`, `land_again` (relands) and `PRLanding.land/2` leave the stage
alone and the Oban job (max 3 attempts) runs the landing again. Only the last attempt still bounces, as
a gate cut off three times does; its message now reads "the merge queue was cut off three times", since
the fetch is not the gate.

## Which failures change their outcome

Only "could not fetch origin", from `Merge.merge/3` and `Merge.stack/3`: it was a bounce to build,
it is now a retried landing. A conflict, a red gate, a missing branch or a repo with no origin keep
their handling. `PRLanding`'s own fetch of the PR branch is untouched.

## How it was checked

`menard run test test/server/workline_merge_test.exs test/server/workline_test.exs:583` in `server/`,
red first (git really answered `cannot lock ref … main.lock: File exists` under a held lock), then
green: a lock on `refs/remotes/origin/main` held 400ms then removed lets `merge/3` and `stack/3`
proceed; one never removed gives `{:error, {:interrupted, …}}` after bounded tries; `land_queued/2`
with a merger that says could-not-fetch leaves the stage at review.
