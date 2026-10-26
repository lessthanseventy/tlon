No free reviewer is at the builder's grade (greybeard); tzinacan (deepseek-flash grade) leads this review.

APPROVE (#391). Read the diff only; I did not run the tests.

- `Staff.start_session` refuses a paneless newcomer when a live session with a pane exists. The check runs inside the transaction, and the partial unique index still guards a concurrent race. A newcomer with a pane supersedes as before, so a restarted pane keeps working.
- `Register` returns `superseded: true` with stand-down text. The adapter sets `sessionId = 0` and `superseded = true`, and registration is cleared, so it does not re-register every poll. It reclaims the seat when `take_wakes` returns an array again, which is the existing path.
- `Wake.seated?` now requires the live session's `pane_ref` to match a pane in the thread's window. A live row with no window, beside a dead windowed row, is no longer a seat.
- `Tmux.parse_windows` gained `pane_id` as a trailing field and shorter lines still parse. Tests were added in the staff, wake and mcp server test files.

Behaviour change to note: a live session registered without a `pane_ref` is now never "seated", so its wakes are let go unpaged. That matches the design (nothing can drain wakes for a paneless session) but is a visible shift from before.