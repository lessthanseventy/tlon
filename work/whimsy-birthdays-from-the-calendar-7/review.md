APPROVE

Read the full diff main...HEAD (12 files). The recorded `mise run check` run in the brief is green; I did not re-run it.

**Server**
- `Feed.celebrations/2` takes only all-day events (`dtstart` is a `%Date{}`), so timed events like "Birthday sync" are excluded. The yearly rule matches on month and day and not before the start year.
- The cache is keyed by day and cleared on both `:refresh` and `:fetched`, so `Office.status` polls don't re-parse the feeds. The caching test covers this.
- The `:fetched` cast is async, so the `GenServer.call` in `status/0` is never blocked behind a fetch.
- `Calendar.celebrations` returns `[]` when the server is off, and the office test covers that case.

**Office**
- Bunting, the cake and the `moment` weighting are all gated on `celebrations`. The room is unchanged when there are none.
- The frame tests run under a fixed `Math.random`, as the last commit intended.
- `office/AGENTS.md` is updated in the same change.

**Non-blocking nits (nothing to fix before merge)**
- A Feb 29 yearly birthday only shows in leap years.
- The yearly `UNTIL` and `COUNT` are ignored. The `@doc` says so.
- In `office/test/pastimes.test.ts` the `moment` import sits after the type import.
- The cake and bunting pixel placement is unseen. No live drive of the office was run, so it is not checked on screen.