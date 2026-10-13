# Pin intake and continuation under pencils down

Closes #179.

Intake auto-start and the continuation nudge ignoring the pause was already fixed on main by #172 (2bdf1d3, live since release 958fe83). This PR is tests only; production code is unchanged.

The tests pin that fix:
- `pause_test.exs`: while paused, intake's 30-minute fallback starts nothing; back to work, it starts the ticket.
- `maintain_test.exs`: `Continuation.run` nudges no quiet workline under pencils down, and nudges it once the office is back to work.

Not covered here: `staff_child`, `/api/tickets/:id/start` and `ticket-start` don't check Pause. That is #262.
