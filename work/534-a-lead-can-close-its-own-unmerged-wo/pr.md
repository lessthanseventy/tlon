finish: a lead stands its own unmerged workline down with superseded_by or abandoned

`finish` refused any workline GitHub hadn't merged and never named the door out, so a lead whose
workline the operator stood down could not close it (#534).

- `finish` takes optional `superseded_by` / `abandoned`; on an unmerged workline they close it through `Channel.close_as/2`, the same path as `close_thread` (superseded → ticket done, abandoned → ticket back to the backlog, why appended to its body).
- Without a why the workline still stays open, and the answer now names both fields.

Not in this change: unlinking the ticket's `promoted` row on abandon, so `promoted_thread_id` clears (#80 still shows 316). Open.
Checked: the two new `server_test.exs` cases red before (closed nil / thread still open), green after; the file's 83 tests, 0 failed. The full gate is not run from this seat.
