# #679 — session-stamped authorship on messages, events and tickets

Fix half of #414. Goal (operator, msg #15251): **make authorship verifiable.** Rows keep only an author
*name*, so when two live sessions share one seat (QA pass #8669: session 954 on t281 %9 filed it, session
947 on thread 1 denied it) a denial cannot be checked against a record. Nothing was forged; nothing is provable.

## Requirements

1. **Migration** (one, nullable, no backfill): `session_id` FK → `session(id)` on `message`, `ticket`, `event`.
   `ON DELETE SET NULL`-style safety is moot (sessions are ended, not deleted) — plain FK, indexed on none (read by row, never queried by session).
2. **Stamp from the connection, never a parameter.** The value is `Server.MCP.Identity.session_id` (the
   token-resolved live session for the thread+agent). Set it with `put_change` *after* `cast`; `:session_id`
   is never in a cast list, so a tool param, a `post_message` arg or a ticket map cannot assert it.
   Paths: `Channel.post` (via `Message.post_changeset/2` opts), `Dossier.record_check` (→ `record_event`),
   `Tickets.file` (the `file_ticket` tool in `mcp/tools/workspace.ex`), and `Workline.qa_verdict/5` (session
   passed in `opts`, flows to its `record_check`). The `qa by <seat>` `cmd` string is **unchanged**
   (`Diary.verdict/1` parses it); the session rides the event's FK.
3. **Render** `"<seat> · pane <thread-window> <pane_ref> · session <id>"` (e.g. `nolan · pane t281 %9 · session 954`)
   on: the `qa by` check line, the QA brief (`post_brief` "✓ QA passed"), the ticket view (`MCP.Brief.ticket/1`),
   and `get_message`. Pane/thread come from joining the `session` row at render time (`pane_ref`, `thread_id`);
   the row survives `ended_at`, so a dead session still renders. One helper (`Server.Authorship.label/1`) owns the format.
4. **NULL means unknown.** Rows before the migration, system authors (`tlon`, `grader`, scheduler, any
   non-MCP caller of `Channel.post`) and MCP calls before `register` binds a session all keep NULL and render
   `<author> · session unknown`. No backfill, no inference.

## Out of scope (YAGNI)

Other `record_event` callers outside MCP tools, `review_verdict` display, UI/office rendering beyond the
four surfaces, any query/filter by session, forged-session defence beyond "comes from the token".

## Design notes / risks

- Pre-`register` calls and pre-migration rows are indistinguishable (both NULL). Accepted: both honestly "unknown".
- Identity's session is resolved per (thread, agent) at read time (`Tokens.live_session_id`); two sessions of one
  seat on *different threads* therefore stamp differently — the exact case of #8669. Two live sessions of one seat on the *same* thread is
  prevented by the partial unique index, so not a case.
- `qa_verdict` is the one signature change (`opts[:session_id]`); all other callers unaffected (default nil).

## Acceptance (test-first, `mise run check`)

1. Two sessions of one seat on different threads each post a message, record a check and file a ticket; each row carries its own `session_id`.
2. A system author (`tlon`) post keeps `session_id` NULL and renders "session unknown".
3. `qa_verdict` writes a `qa by` check whose event has the caller's session, and its line renders `nolan · pane t281 %9 · session 954`.
4. A `session_id` smuggled in tool params / attrs is ignored (stays the connection's value).

## Landing

Includes a migration → its landing gate is the operator's (constraint #4242); recommendation: approve (additive, nullable, reversible by dropping three columns).
