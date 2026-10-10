APPROVE

Scope: one commit (6b68385), test-only: `server/test/server/shifts_test.exs` +10 lines. No production code changed. The branch was reset onto main (the original design was superseded by Server.Jobs.ShiftBack + Shifts.offer_day/3 already on main), so the diff is just the one missing test.

Checked:
- Setup follows the sibling tests (lobby thread, switch to night, offer_day, answer the ask).
- Answer "2" matches option order in `Shifts.offer_day/3` (`["day shift back", "stay on nights"]`), so it exercises the "stay" path.
- Asserts the crew stays "night" and the ask is closed; not vacuous, since it first asserts exactly one open ask.
- `mise run check` green on this branch per the recorded verify (server: 9 passed, 0 failed).

Findings: none blocking. No follow-ups.
