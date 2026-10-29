Intake's 30-minute staffing fallback now waits on a manager's open triage (closes #521).

`Intake.start_stalled` read nothing from the channel, so a ticket the manager was still triaging (consult/ask naming it) could be staffed twice. Now the 30 minutes run from the newest of: the ticket's `updated_at`, a manager message naming `#N` on the workspace root thread after the route, a consult naming `#N` after the route, or the resolution of the manager's operator ask naming `#N`; while that ask is open it blocks the fallback outright. `held` is unchanged. When the fallback does fire, it also posts on the root thread naming the new thread.

Checked: `menard run test --in server test/server/intake_test.exs` (25 tests, 0 failures; 7 new: deferred by manager message, deferred by a consult, a pre-route consult ignored, blocked by the manager's open ask then fires once resolved + 30 min, a just-resolved ask still defers, root-thread post, number-prefix guard), `menard run check --in server`.
