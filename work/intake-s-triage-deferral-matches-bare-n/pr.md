# intake: a thread or PR number no longer defers a ticket, and a deferral is noted

Closes #720.

`Server.Intake.naming/2` matched a bare `#N`, so a manager's "PR #N landed" or a consult's "see thread #N" deferred ticket N for 30 minutes, silently. A consult in another workspace naming `#N` deferred it too.

- `naming/2` skips a `#N` preceded by `thread ` or `PR ` (case-insensitive), and scopes the match to the ticket's workspace. A bare `#N` still defers, so "#864 → #552" still works.
- A deferral past `after_s` posts one tlon-authored ⏱ line on the root thread. It has no `consult_id`, so it cannot defer the ticket itself. A later pass adds no second line while a newer one names the ticket.

Checked:
- `mise run`-equivalent: `menard run check --in server` with the seat's `TLON_THREAD`/`TLON_LOBBY` unset: 2813 tests, 0 failures.
- `test/server/intake_test.exs`: 36/36. The four new tests (consult "see thread #N", PR #N, cross-workspace consult, ⏱ note) failed red before the change; the "#N → #552" test stays green.
- One unrelated seat-environment leak found on the way: see the ticket filed against #756.
