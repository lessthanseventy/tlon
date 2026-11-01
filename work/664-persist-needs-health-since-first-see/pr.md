# Persist Needs health first-seen across restarts

Closes #664.

`Server.Office.Needs.health_since/1` kept each box-health problem's first-seen time in
`persistent_term`, so a node restart reset every health item's `at`: a put-away item came back until
put away again, and the 30-minute fail-open clock started over.

What changed:

- New table `health_since` (`what` text PK, `since` utc_datetime), same schemaless shape as
  `need_heard`; migration `20261031120000_health_since.exs`, listed in the doctor's table test.
- `health_since/1` now reads and writes that table: a row is inserted when a problem is first seen
  (`on_conflict: :nothing`), deleted when its problem no longer holds, and the returned `at` is the
  stored `since`. Reads hit the db; `health/0` already rescues, so a db failure leaves health items out
  as before.
- `needs_test.exs` and `smoke/fixtures_test.exs` go through the table instead of `:persistent_term`.
  The test that pinned the reset is replaced by one asserting a seeded row is the item's `at`, and a new
  test covers the row clearing when the problem resolves and a fresh clock on its return.

Out of scope, per the tech lead's read: `Attention.tmux_down/2` has the same persistent_term reset and
gets its own ticket.

Checked: `menard run test --in server test/server/doctor_test.exs`, `test/server/office/needs_test.exs`,
`test/server/smoke/fixtures_test.exs` red before each step and green after; `server:check` via
`run_task` on the committed head.
