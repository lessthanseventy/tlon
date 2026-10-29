Intake's 30-minute staffing fallback now waits on a manager's open triage (closes #521).

`Intake.start_stalled` read nothing from the channel, so a ticket the manager was still triaging (consult/ask naming it) could be staffed twice. Now the 30 minutes run from the newest of: the ticket's `updated_at`, a manager message naming `#N` on the workspace root thread after the route, or a resolved consult naming `#N`; an open consult naming it blocks the fallback outright. `held` is unchanged. When the fallback does fire, it also posts on the root thread naming the new thread.

Left open: a consult that is never resolved blocks the fallback forever (uncapped, per the plan).

Checked: `menard run test --in server test/server/intake_test.exs` (22 tests, 0 failures; 4 new: deferred by manager message, open/resolved consult, root-thread post, number-prefix guard), `menard run check --in server`.
