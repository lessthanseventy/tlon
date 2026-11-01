APPROVE — #710

Right then. Read the diff against origin/main.

- `workline.ex` escalate now passes `trust: Server.Trust.record(&1.name)`. This matches the two other `Roster.pick` callers (lines 1395 and 1462), so escalate no longer ties on bench order.
- The `@spec` names `optional(:trust)` with the `led`/`first_time` shape that `trust_rate/1` matches on. Correct.
- The neutrality test now puts the zero-record seat first and asserts it wins. The old order passed even if the default were 0.0, because bench order broke the tie. The new order only passes at 0.5, so the test now has teeth.
- The new continuation test is sound by inspection: zelda has 2 first-time builds (rate 1.0), ireneo has none (0.5), and ireneo is seated first. Without the trust key, bench order would pick ireneo.

I did not run the suite. The pr.md cites a green `menard run check --in server` (2590 tests) recorded as event 15564; I take that as theirs, not verified by me.

No blocking findings. restaff/restaff_miss are explicitly split off, so I'm not asking for them here.