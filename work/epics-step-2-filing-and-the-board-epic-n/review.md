APPROVE — epics step 2 (filing + board data)

Read the full code diff (main...HEAD). The checks on the thread show `mise run check` green and verify recorded; I did not re-run the gate myself.

What I checked by reading:
- `Tickets.file/1`: `epic_id` is popped and the insert plus the parent link run in one transaction. A refused parent rolls back, so no orphan ticket is filed. A nil `epic_id` keeps the old path.
- `Tickets.adopt/2`: all or nothing. The first refusal rolls back and returns `{:error, {id, cs}}`, which the CLI turns into a message that names the ticket.
- `Room.board/1`: epics and children are grouped, `loose` holds tickets with no epic, and `next` follows intake's own rule (backlog, unblocked, not held). `effective_priority` is the higher of the child's and its epic's priority, the same as intake's `rank`. Reusing `Ticket.urgency/1` and the now-public `Intake.held?/1` instead of copies is a good change.
- The API route (`board` added to the read whitelist), the `epic_id` field on `file_ticket` and on the brief, and the CLI verbs. The CLI validates ids as integers and escapes titles and bodies before they reach rpc.

Nits, none blocking:
- The `board/1` docstring calls an epic's `status` "derived", but it returns the raw `e.status`. Either reword it or derive it later.
- `tlon-cli.sh epic-new` calls `shift 2` after reading `$1` and `$2`. That works, but it is fragile if a later edit adds a third positional argument.