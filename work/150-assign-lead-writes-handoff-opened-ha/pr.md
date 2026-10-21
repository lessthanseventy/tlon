assign writes handoff_opened; the post's hand-off reads it

`Server.Staff.assign/2` records a `handoff_opened` event (`from`/`to` lead names) when a thread's lead
changes from one agent to another; a first staffing or re-seating the same lead writes none. The
activity feed (`Server.Office.Room.activity/2`) already carried events, so it now gives a
`handoff_opened` row the old lead as `who`, and `handoffFrom` (office/kit/plane.ts) reads the newest
such row for the thread within a minute instead of `visits`. It no longer needs a live uqbar session,
and a true lead reassignment now leaves the record the old doc comment said it didn't.

Closes ticket #150.

Checked: new tests in `staff_test.exs`, `office/room_test.exs` and `office/test/plane.test.ts` went red
first; `menard run check --in server` green (1973 tests, 0 failures); `bun test` in office green on a
rerun (one earlier run in the sandbox showed 1 fail/1 error, not reproduced on two reruns).
