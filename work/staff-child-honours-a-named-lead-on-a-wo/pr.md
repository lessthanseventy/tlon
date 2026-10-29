staff_child with a named lead on a workline seated two builders: the stage's pick at open, then the named lead on top. The named lead now goes into `Workline.open/1` (`lead:`), which makes one pick under `lead_for`'s rule (a fit lead of the stage's kind who is free wins; otherwise the stage's pick leads and the thread says why). staff_child no longer re-assigns for worklines and replies with whoever actually leads. Plain threads are unchanged.

Closes #551.

Checked: new tests in `server/test/server/mcp/server_test.exs` (free named builder → one leads-line and that lead; busy named lead gives way and says so) — red before, green after; `menard run test --in server` on server_test and workline_test green; `menard run check --in server`.
