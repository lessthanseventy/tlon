Reviewed by tzinacan, who is below the builder's grade (greybeard): no free reviewer was at that grade, so the server named me lead.

**Verdict: approve.**

What I checked, by reading `git diff main...HEAD`:
- `Server.Office.tickets/1` now keeps epic rows even when their status is "doing". It adds `kind` and `epic_id`, and merges `done`, `total` and `next` from `Room.board(ws).epics`. The new ExUnit test covers an epic with progress, a child naming its epic, a loose ticket, and a done child being dropped.
- `boardColumns` hides children (`epic_id != null`) and emits one `epic` act per epic. The new `board.test.ts` covers the title format, the no-free-child case and `epicChildren`.
- The TUI has a new `epic` mode, handled in `loadCard`, `act` and `detail`. The detail view lists the epic's children, and a ticket's detail shows its parent epic. The wide room treats `epic` like `ticket` for id and colour. `office/AGENTS.md` is updated in the same change.

I did not run the tests or the gate. The gate result on the thread is the evidence, and I did not recheck it.

Non-blocking notes:
1. `epic_of/1` costs one query per ticket in `tickets/1`, and `Room.board/1` repeats the ticket queries per workspace. It is fine at office scale. If the snapshot gets slow, batch it from the `parent` links.
2. A child with status "doing" is hidden from the epic's detail rows. That matches the board, where doing work appears as a thread, so no change is needed.