Verdict: approve. No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (deepseek-flash). Weigh accordingly.

Diff read (needs.ex, needs_test.exs); not run by me — verify owns the gate.

- The gate item's age now comes from the parked notice ("⏸ workline <slug> is parked at <stage> — …", latest by id), falling back to thread created_at. The prefix matches `Server.Workline.Brief.gate_message/2` exactly (checked).
- Tests cover both directions: an old workline that just parked stays with Uqbar; a park older than uqbar_route_minutes fails open with the right why.

Non-blocking: see follow-ups.