Ticket: the intake (`Server.Intake.run/1`) starts the next backlog ticket per workspace while fewer than
`cap` worklines are in flight, counting tickets it has already routed (status `todo`, a thread promoted
from them) as in flight. Bug: a `todo` ticket whose promoted thread was **closed** without merging still
counts, forever — nothing else will ever move it on — so it holds a workline slot and the workspace's
intake stalls.

Fix `in_flight/1` in `lib/server/intake.ex`: a `todo` ticket that has a `Server.TicketThread` of kind
`"promoted"` whose `Server.Thread` has `state == "closed"` must not be counted (neither as being worked
nor as open). `todo` tickets with no such thread, or with a still-open one, count exactly as before.

Observable behaviour: with `cap: 1`, a workspace holding one such stuck `todo` ticket and one `high`
backlog ticket, `Intake.run(cap: 1, route: fun)` calls `fun` with the backlog ticket. Add a test to
`test/server/intake_test.exs`; keep `mix test` green.
