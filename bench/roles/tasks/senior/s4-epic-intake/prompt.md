Ticket (epics, step 2): teach the intake which ticket to start next when epics exist. A ticket of
`kind: "epic"` is a container, never work; its children are linked by `parent` links
(`Tickets.link(epic.id, child.id, "parent")`; `Server.TicketLink`). Change `Server.Intake.next(ws_id)`
(`lib/server/intake.ex`), which returns the backlog ticket to start next in a workspace or nil:

- Never return an epic.
- A child's effective priority is the higher of its own and its epic's (`high` > `med` > `low`; an
  epic's low priority never lowers its child's).
- Within one epic only its lowest-`sort` unfinished child is a candidate (step order); the others wait
  until it is done.
- Among equally urgent candidates, a child of an epic whose status is `doing` goes before everything
  else (finish started epics); the remaining ties keep the existing order — newest `sort` first, then
  highest id — and tickets that are blocked (`Tickets.blocked_in_workspace/1`) or labelled `held` are
  still skipped.

Loose tickets (no epic) keep behaving as today. Add tests to `test/server/epics_test.exs` (it has
`epic/3` and `file/3` helpers); keep `mix test` green.
