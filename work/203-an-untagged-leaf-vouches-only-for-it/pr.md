Closes #203.

`Staffing.windowed?` counted an untagged leaf (no `@funes_agent`) as the window of every agent's session on its thread, so after a switch the going lead's idle session was never ended and the roster kept listing it. An untagged leaf now vouches only for the thread's lead (`Channel.thread_lead/1`); a tagged leaf still vouches for its own agent.

Checked: two new tests in `staffing_test.exs` (tagged and untagged leaf on a restaffed thread: old lead's session ended, new lead's kept); the untagged one was red before the fix. `menard run check --in server`: 2176 tests, 0 failures.
