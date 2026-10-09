NOTE: no free reviewer was at the builder's grade (greybeard); reviewed by tzinacan at a lower grade — weigh accordingly.

# Review: one parent enforced in the DB; epic status never cast (a85c730)

**Verdict: approve.**

Verified by reading the diff and the baseline schema. I did not run the suite; the recorded `mise run check` passed on this branch.

- Migration: `ticket_link.id` is BIGSERIAL, so "keep earliest by id" is well defined. The dedup DELETE runs before the partial unique index is built, so the index can build on dirty data. `down` drops the index. Deleted duplicate rows are not restored on rollback, and the migration's comment says as much.
- Changeset: `unique_constraint(:to_id, name: :ticket_link_one_parent)` turns a race loss into the same "already has a parent epic" error as the pre-check. Without it the race would surface as a `Postgrex.Error`.
- Epic status: `update_changeset` drops `:status` from the cast for epics. The other `update_changeset` callers (sort swaps at `tickets.ex:348-349`) only touch `sort`, so nothing legitimate loses a field.
- Tests: the raw-INSERT test proves the DB refuses a second parent. The migration test proves dedup keeps the earliest link and the index then holds, and it cleans up its `schema_migrations` row.

Nits, no change requested:
- `ticket.ex`: the `if` inside `cast(...)` is dense; a small private `mutable_for(ticket)` would read better.
- The migration test drops and recreates the index on the shared test DB. It is `async: false` and calls `TestDB.clean!`, so it is safe as written.