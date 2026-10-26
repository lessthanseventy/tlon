# A gate need's age is its park, not its thread's birth

Closes #650.

`Needs.wait/2` built a gate item with the thread's `created_at` as its `at`. `route_item/4` fails an
item routed to Uqbar open to the operator once `at` is older than `uqbar_route_minutes`, and
`NeedsPage` only pages the `uqbar` group — so any workline that spent more than 30 minutes before
its gate passed up at once as "Uqbar did not route it in time" and was never paged (gate:363).

Nothing records the park as an event, but both park paths (`park_on_operator/2` and `flag/2`) post
the "⏸ workline <slug> is parked at <stage>" notice when `awaiting` is set. The gate item now carries
that notice's `created_at`; only a thread with no notice falls back to its birth. `paged?` and
`verdict_row` compare against the same `at`, so they follow. Question items already use their own
message's time and were not affected.

The notice's wording has one source: `Brief.parked_prefix/2`, which `gate_message/2` builds on and
`Needs.gated_at/1` matches with a trailing `%`, so a reword cannot silently age gates from their
thread's birth again.

Checked: two new tests in `needs_test.exs` (an hour-old workline that has just parked routes to
Uqbar; a park 31 minutes old fails open), red before the fix, green after; a `workline_brief_test.exs`
test that the gate notice opens with the shared prefix; `needs_test.exs` (77), `workline_brief_test.exs`
(12) and `needs_page_test.exs` (7) green; full `mise run check` on the head via run_task.
