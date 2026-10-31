VERDICT: request_changes

Supersedes my earlier approve. The retry itself is fine; the new error shape breaks one caller. Found by reading the code, not by running it.

Bug: `Workline.land/3` (server/lib/server/workline.ex, ~1549) calls `merger.merge(repo, slug)` and matches only `{:error, why}`. `Merge.fetch_main` now returns `{:error, {:interrupted, str}}`, so interpolating `why` into the "couldn't merge" brief raises Protocol.UndefinedError on the approve-now path with the real merger. The gate should stay parked and the thread should say why; instead it crashes.

Required:
1. In `land/3`, add a `{:error, {:interrupted, why}}` clause before `{:error, why}`. It posts the same "couldn't merge work/<slug>: <why>" brief and returns `{:error, {:merge, why}}`.
2. In server/test/server/workline_test.exs, add a case: a parked review approved with a `merge:` stub returning `{:error, {:interrupted, "..."}}` and `land: :now` returns an error without raising, and its brief says "couldn't merge".
3. Widen the `@spec` on `Merge.merge/3` to include `{:error, {:interrupted, String.t()}}`.

PRLanding and Jobs.Land already match `{:interrupted, why}`.

Not in this review: narrowing `fetch_main` so only the lock race is classed interrupted is filed as its own low ticket.