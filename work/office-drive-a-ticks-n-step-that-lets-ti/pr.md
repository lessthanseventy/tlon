office-drive: a ticks:N step lists every balloon seen

`scripts/office-drive.sh` gets a `ticks:N` step. It sends no keys: it lets N sim ticks (100 ms each) pass, captures the screen every 10 of them, and prints the text seen in any capture before the frame. A balloon that came and went still shows, so QA can see a staggered cast reaction whole instead of only the frames that happened to land on it. The drive-office skill and the `drive_smoke` keys doc name the step.

Out of scope, per the ticket's decision: no TUI change, and no export of balloons from the sim. An exact who-said-what would be a second ticket.

Closes ticket #574.

Checked:
- `scripts/office-drive.test.sh`: `ticks:3` sends no keys and `ticks:20` makes 3 captures and lists the balloon. Both were red before the step; the existing key cases stay green.
- `menard run test --in server test/server/jobs/smoke_test.exs test/server/office_drive_script_test.exs`: 28 tests, 0 failures.
