# Session-stamped authorship on messages, events and tickets

Closes #679 (the fix half of #414). Makes authorship verifiable: a row keeps the **session** that
wrote it, not only a name, so a denial like QA pass #8669's ("that wasn't me") is checked against a
record.

## What changed

- **One additive migration**: nullable `session_id` FK to `session` on `message`, `ticket` and
  `event`, `on_delete: :nilify_all`. No backfill; a row from before, a system author's (`tlon`) or a
  pre-`register` call's is NULL and renders `session unknown`, and so does one whose session a
  thread's purge deleted: a ticket, a check or a post on another thread outlives it.
- **Stamped from the connection, never a parameter.** `Channel.post/2`, `Dossier.record_event/2`,
  `Dossier.record_check/2` and `Tickets.file/2` take `session_id:` as an opt, put after cast; the
  field is in no cast list, so attrs or tool params cannot assert it. The `post_message`, `finish`,
  `record_check`, `file_ticket` and `submit_qa` tools pass `identity.session_id` from the token's
  claims. `Workline.qa_verdict/5` takes `session_id:` in its opts; the `qa by <seat>` cmd string
  is unchanged (`Diary.verdict/1` parses it).
- **Rendered** by `Server.Authorship.label/2` (`nolan · pane t281 %9 · session 954`), the one place
  the format lives: `get_message` (`by`), the ticket view (`filed_by`), a check (`by`; a `qa by`
  check names its seat) and the QA pass/fail posts.

## How it was checked

- `test/server/mcp/authorship_test.exs`: one seat with two live sessions on two threads drives
  the three tools through `TokenValidator`'s own claims; each row carries its own session id, a
  `tlon` post stays NULL.
- `test/server/workline_qa_test.exs`: a QA pass's check event carries the QA seat's session and
  the `qa by` line and QA brief render the label.
- `test/server/session_stamp_schema_test.exs`, `session_stamp_test.exs`, `authorship_test.exs`:
  schema fields present, smuggled `session_id` attrs ignored, NULL/no-pane/ended-session labels,
  and `delete_thread` on a session's thread leaves its ticket, check and off-thread post at NULL.
- `menard run check --in server` green (format, warnings-as-errors, credo, the suite).

## Landing

Includes a migration, so the landing gate is the operator's (#4242). Recommendation: approve. It
is additive and nullable; revert by dropping the three columns.
