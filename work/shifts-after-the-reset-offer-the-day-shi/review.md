APPROVE

Scope: test-only. `server/test/server/shifts_test.exs` +10 lines, one test ("answering \"stay on nights\" leaves the night crew on"). No production code changed. The original design was superseded by Server.Jobs.ShiftBack + Shifts.offer_day/3 on main; the branch carries only the one missing test.

Checked (re-read the diff at this stage):
- Setup mirrors the sibling tests: lobby thread, switch to night, offer_day, answer the ask.
- Answer "2" is the second option ("stay on nights"), so it exercises the stay path the sibling test leaves uncovered.
- Not vacuous: it first matches exactly one open ask, then asserts the shift is still "night" and no asks remain open.
- Verify recorded `mise run check` exit 0 on this branch; I did not re-run it.

Findings: none blocking. No follow-ups.