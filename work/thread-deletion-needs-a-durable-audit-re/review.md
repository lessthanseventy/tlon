Verdict: APPROVE

Scope: commit 3bc4104 (delete_thread records a durable thread_deleted event).

What it does: `purge_thread/1` banks a `Server.Dossier.record_event/1` call with kind
`thread_deleted`, correlation `thread:<id>`, and detail `thread_id`/`title`/`deleted_by` —
inserted inside the same transaction, after the thread's child rows are nulled/deleted but
before `Repo.delete!(thread)`. A migration widens the `event_kind_check` CHECK constraint to
add `thread_deleted`; `Server.Event`'s moduledoc kind list is updated to match.

Checks performed:
- Confirmed the CHECK constraint name (`event_kind_check`) matches Postgres's auto-generated
  name for the unnamed inline CHECK in the baseline migration (`20260918000000_postgres_baseline.exs:211`)
  — the `drop constraint/create constraint` pair is dropping/recreating the right object.
- Confirmed no event thread_id FK hazard: the new event is inserted with no `thread_id` in
  attrs, so it lands with `thread_id: nil` from the start — it doesn't depend on the later
  `Repo.delete!(thread)` succeeding to avoid a dangling FK.
- Confirmed `deleted_by` follows the same `Application.get_env(:server, :operator, "andrew")`
  convention already used elsewhere (`workline/continuation.ex`'s `stuck/2`) — there is no
  per-call actor threaded into `delete_thread/1` today (checked all three callers: `server.ex`,
  `mcp/operator_api.ex`), so this isn't a regression or a missed parameter, just the existing
  single-operator assumption.
- Ran `menard run test --in server test/server/channel_test.exs` unsandboxed (DB over a unix
  socket, so sandboxed menard fails with `ECONNREFUSED`/`not owner` — expected, not a bug): 56
  tests, 0 failures, migration applied cleanly.

Matches the ticket: who (`deleted_by`), when (`created_at`, truncated to the second, same as
every other Event), title, and thread_id all survive the delete. Follows the existing
append-only Event pattern exactly, as asked — no new mechanism invented.

Nits (non-blocking):
- `event.detail["thread_id"]` is redundant with `correlation` ("thread:<id>") but harmless —
  cheap belt-and-suspenders for a human reading `detail` without parsing `correlation`.
- No test asserts `correlation` or the untested extra `thread_id` detail key, but the ticket's
  three required fields (who/when/title) are all asserted in `channel_test.exs`.