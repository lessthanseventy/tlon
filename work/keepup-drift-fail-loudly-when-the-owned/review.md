APPROVE — keepup-drift-fail-loudly-when-the-owned (19351af)

Both asks from #86 are met in `route/4` (keep_up.ex):
1. No lobby → the owned repo's drift falls back to the keyed `{:drift, repo}` operator note (new test covers it).
2. `Tickets.update`/`file`/`post` results are matched with `{:ok, _}` in a `with`, so a failure falls through to the same note instead of being discarded.

Checked: `:forwarded` calls `Rollout.clear({:drift, repo})`, so the fallback note doesn't go stale. Server check was green on the branch (exit 0).

Nits, not blocking:
- The failed-update/file branch has no test (builder couldn't force the failure); it shares the fallback line with the tested no-lobby case.

Verified by reading the diff; I did not re-run the suite.