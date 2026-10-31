No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (deepseek-flash class), so read as a careful but lower-grade pass.

# Verdict: approve

Merge queue: retry a fetch that loses the origin/main ref lock (#645).

## What I checked (read the diff, grepped callers; did not run the suite)
- `fetch_main/2` replaces both `fetch origin main` calls (`merge/3`, `stack/3`). It retries up to 3 tries (250 ms, then 500 ms) only on "cannot lock ref". Any other fetch failure, or a lock that never clears, returns `{:error, {:interrupted, why}}`.
- `merge/3`'s `with` has no `else`, so the interrupted tuple passes through to `Workline.land_queued`, `PRLanding` and `Jobs.Land`. All three already handle `{:interrupted, _}` (retry, with the last attempt bouncing).
- `stack/3` passes `{:error, _}` through. Both train callers handle only `{:gate, _}` specially, so an interrupted fetch falls to their generic `{:error, _}` branch (land solo / leave unverified). Safe.
- The message change in `workline.ex` ("cut off three times", not "the gate") is accurate now that the fetch can also cause it.
- Tests cover a held lock that clears (`merge/3` and `stack/3`), a lock that never clears (branch tip unchanged, interrupted), and `land_queued` leaving the stage at review. The nowhere-remote test is updated to the interrupted shape.

## Nits (not blocking)
- A permanently bad origin URL is now retried by the Oban job before it bounces: a few extra attempts of delay, nothing worse.
- The 250/500 ms backoff is hard-coded; fine for a winner that finishes in tens of ms.
- The tests that hold the real lock for 400 ms are timing-dependent, but the margin looks adequate.