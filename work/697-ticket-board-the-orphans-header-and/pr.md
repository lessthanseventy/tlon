Closes #697.

The orphans header counted every open loose ticket, but the rows under it drop a loose ticket that is at work (`doing`, no epic). Two loose tickets at work read "5 open" over 3 rows.

`open_counts/2` in `Server.Office.Room` now leaves a started loose ticket out of `loose_open` and keeps it in `open_total`. The header, the whiteboard's "N loose" sticky and the rows now use one meaning of loose, decided on the server; `crew.ts` is unchanged apart from one doc line in `types.ts`.

The existing `Room.board` open-counts test asserted `loose_open == 2` with a started loose ticket among them. That asserted the disagreement, so it now asserts 1.

Checked:
- RED: `room_test.exs:349`, `loose_open` left 2, right 1.
- GREEN: `menard run test --in server test/server/office/room_test.exs` → 23 tests, 0 failures.
- `menard run check --in server` → 2559 tests, 0 failures.
- `mise run office:test` → 968 tests, 0 failures.
