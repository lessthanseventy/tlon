No free reviewer is at the builder's grade (greybeard); runeberg leads this review. APPROVE. I read the diff and did not run the suite; verify runs the full gate.

Right then. What I checked:
- `session_id` is `put_change`, never `cast`, in Message, Event and Ticket, so attrs cannot forge the stamp.
- Every MCP write path (post_message, finish, record_check, file_ticket, submit_qa) passes `identity.session_id`. System writers (`Attention`, `Stall`, `Alarm`, seed) keep the default and render `session unknown`.
- The `qa by <seat>` cmd string is untouched, so `Diary.verdict/1` still parses it.
- The latest fixup (7bdbad8) is correct: `purge_thread` deletes a thread's sessions, so a restrict FK would have rolled the purge back on a ticket, event or cross-thread post. `on_delete: :nilify_all` renders those rows as `session unknown`, and authorship_test covers all three.
- The migration is a limit-grade change (schema). It is nullable, has no backfill, and is additive and reversible.

Non-blocking, in follow_ups:
1. N+1: `Brief.message/check/ticket` each do `Repo.get(Session, id)` per row (up to 50 per `get_messages`). Batch-load.
2. `check_by("qa by " <> seat, ...)` trusts the cmd string for the seat name; the session part is truthful and the seat part is self-reported.