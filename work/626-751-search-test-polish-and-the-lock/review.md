APPROVE. Right then: the diff reads clean and the suite is green (menard run test search_test.exs: 18 tests, 0 failed, run by me).

Checked:
- Lock waits bounded at 5s on both ends (assert_receive and the holder's `after`), so an unbounded query finishes red rather than hanging.
- Telemetry handlers are exported funs, detached in on_exit, so a failed assertion no longer leaks one.
- Handler now stays attached to test end. The holder's own LOCK query matches neither after_sql nor until_sql, and the module is async: false, so no cross-test trigger.

Fragility, not blocking (follow-up): captured_history_query takes the FIRST {:sql, ...} message and asserts it is the idf query, so it depends on query order inside Search.history/3. Select the matching message instead.