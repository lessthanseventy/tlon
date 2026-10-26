Closes #391.

A session with no pane could take a seat from a windowed one, and the overdue-wake guard accepted a windowless live row beside a windowed dead one.

- `Staff.start_session`: a register with no `pane_ref` no longer supersedes a live session that has one (`{:error, :seat_held}`, no row written). The `register` tool answers `superseded` and `mod.ts` stands the newcomer down; a newcomer with a pane still supersedes, so a restarted pane works.
- `Wake.seated?`: the live session's `pane_ref` must be a pane in the thread's window. `Tmux.list_windows` now carries `pane_id`; a live session with no pane_ref is not seated.

Checked: new tests for each rule (staff_test, server_test register, wake_test with the ticket's fixture) went red then green; `menard run check --in server` below.
