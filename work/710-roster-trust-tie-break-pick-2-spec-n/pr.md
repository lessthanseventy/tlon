Roster trust tie-break follow-ups from #417 (ticket #710): three small fixes to the record tie-break.

- `escalate` now hands `Roster.pick` each senior's `Server.Trust` record, like `suggest_lead` and `restaff` already do. Tied seniors used to fall back to bench order; the better first-time-landing record now wins. Test: `escalate: tied seniors go to the better trust record` (red on bench order before the change).
- `pick/2`'s `@spec` names the optional `trust` key.
- The "no record is neutral" test puts the `led=0` seat first and asserts it wins: a neutral (0.5) record ties and bench order decides, while a worst (0.0) record loses. Mutating the no-record default to 0.0 turns the roster tests red.

Not touched: `restaff` and `restaff_miss` (item 4, split off).

Checked: `menard run check --in server` green, 2590 tests, 0 failures (recorded as `check_passed`, event 15564).
