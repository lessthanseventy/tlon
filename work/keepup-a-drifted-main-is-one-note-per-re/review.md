VERDICT: request_changes (one real bug, small fix)

Spec compliance is good: keyed upsert note (`Rollout.note/2`, `clear/1`), routing to the owning workspace's lobby plus one `drift:<repo>` ticket, a moduledoc line on restart-drops-notes, and tests for the three asked cases.

## Must fix
`KeepUp.drifted(repo, _level)` (keep_up.ex) is a catch-all, so it clears for every non-diverged result. `Publish.follow_main/2` also returns `{:error, why}` (fetch failed, ff refused) and `:skipped` (checkout is on another branch). On a transient network blip, or when someone checks out a feature branch in the main checkout, a still-drifted repo gets its keyed note cleared and its ticket closed "done". The next healthy check then files a new ticket and a new lobby post. That is the duplicate-per-check churn this ticket exists to stop, only slower. The pre-change code ignored these results.

Fix: clear only when main is actually level, and ignore the rest.

    def drifted(repo, :forwarded), do: ...clear note + close ticket...
    def drifted(_repo, _other), do: :ok

`follow_main` returns `:forwarded` when already level: `forward/1` runs `merge --ff-only`, which succeeds as a no-op. Add one test: `drifted(repo, {:error, "x"})` and `drifted(repo, :skipped)` leave the note and ticket in place.

## Minor, no block
- The moduledoc sentence in keep_up.ex runs about 190 chars on one line; rewrap it.
- The spec says the operator hears about drift if the crew can't handle it, e.g. a live session committing to that main. This only pages the operator for unowned repos. emma flagged the choice. Name it as open.
- If the operator dismisses the unowned-repo note, the next check refiles it. Probably intended.

Not run by me: the suite. I read the diff only. The full-check evidence on the thread is the server's.