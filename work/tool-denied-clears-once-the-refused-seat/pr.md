tool_denied clears once the refused seat moves on (#579)

A `tool_denied` item is blocking and has no dismiss path, so a coworker who worked around the refusal and kept building on the same stage saw it return every turn. A post on the thread by a seat that was refused, dated after its last denial, now counts as movement for that item (`Needs.refused_moved/1`); `stalled` is unchanged (chatter is still not movement there).

Not covered: a commit on the branch. `last_moved/2` only sees branch tips through `stalled`'s per-refresh git call; plumbing that into `tool_denied` was left out.

Closes #579 (the other two faults it names landed in 8a3fd15).

Checked: `menard run check --in server` — 2430 tests, 0 failures; two new tests in needs_test (post after denials clears; post before denials, or another seat's, does not), the first red before the change.
