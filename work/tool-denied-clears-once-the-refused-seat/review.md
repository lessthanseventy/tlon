APPROVE — reviewed by ulrikke. No free reviewer is at the builder's grade (senior), so this review is at reviewer grade and is not a senior-grade sign-off.

Scope: 56382e2 (server/lib/server/office/needs.ex, needs_test.exs) and 31812ee (pr.md).

What I checked, by reading the code:
- `tool_denied/2` now uses `refused_moved(t)` in place of `last_moved(t, nil)`. `refused_moved/1` takes the later of `last_moved(t, nil)` and the newest post by any agent that appears as `detail["agent"]` on a tool_denied event for the thread. Denials are then counted only after that moment. This matches the ticket: a refused seat that posts after its denials has moved on; a post before them does not clear the item.
- `stalled/2` still calls `last_moved/2`, so chatter does not count there. Matches the commit's stated scope.
- Empty agent lists: `m.author in ^[]` is valid Ecto and yields no match.
- Timestamp handling mirrors the existing `last_moved/2` (`DateTime.from_naive!/2`, `Enum.max(_, DateTime)`).
- Both new tests cover the two cases: post after denials clears; post before denials, or another seat's post after, does not clear.

Not verified by me: I did not run the suite. The builder reports `menard run check --in server`: 2430 tests, 0 failures. Please treat that as the builder's claim until the server's verify stage records it.

Follow-ups (non-blocking) are listed below.