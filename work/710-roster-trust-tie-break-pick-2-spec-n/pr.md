Roster trust tie-break follow-ups from #417 (ticket #710): three small fixes to the record tie-break.

- `escalate` now hands `Roster.pick` each senior's `Server.Trust` record, like `suggest_lead` and `restaff` already do. Tied seniors used to fall back to bench order; the better first-time-landing record now wins. Test: `escalate: tied seniors go to the better trust record` (red on bench order before the change). The escalation post now states the winner's record ("landed N of their last M builds first time"), so a bad tie-break shows on the thread.
- `pick/2`'s `@spec` names the optional `trust` key.
- The "no record is neutral" test: the zero-first form (a `led=0` seat listed first, asserted to win) could not tell neutral from worst. Under a 0.0 default both rate 0.0 and bench order picks the zero seat, so the test passed either way. The worst-first form does discriminate: a `10, 0` worst record listed first loses to a `0, 0` seat and to a seat with no trust key. Those two cover both `trust_rate` paths (led 0, and no key), and the test is its own so that the 0.0 mutation fails exactly on its zero line.

Not touched: `restaff` and `restaff_miss` (item 4, split off).

Checked: `menard run check --in server` on 225e550, nothing else running: 2591 tests, 0 failures. The worst-first test under the 0.0 mutation: red at its zero line (roster_test.exs:95); unmutated 13/13 green.
