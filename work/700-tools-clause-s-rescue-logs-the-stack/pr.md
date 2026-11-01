# Log the stacktrace when a clause verb raises (#700)

`Server.Source.Tools.clause/6` rescues any raise into an `{:error, message}` reply, which is right for the agent but left no trace of the raise on the server. A real Menard bug in `Clause.replace_body`, `delete` or `insert_after` therefore had no stacktrace anywhere.

Change: the rescue now calls `Logger.error(Exception.format(:error, e, __STACKTRACE__))` before replying. The reply itself is unchanged.

Test: a new case in `tools_test.exs` makes `Menard.Clause` raise inside `Tools.clause` (a non-binary `code`), under `capture_log`. It asserts the reply is a readable error, the log holds the formatted exception and `Menard.Clause` in its stacktrace, and the file is untouched. Red first: the log assertion failed on an empty log; the reply assertions already held, so the raise was real.

Checked: `menard run check --in server`: ok, 2560 tests, 0 failures (recorded as check_passed).

Closes #700.
