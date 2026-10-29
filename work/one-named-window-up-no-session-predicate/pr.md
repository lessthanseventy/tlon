## One named predicate for "window up, no session" (#507, #513, #514)

- **#507** `Server.Coworker.window_only?/2` is the one definition of a tmux window running a seat with no session behind it. `Office.threads/5` reads it for `desk?`, where the inline `live`-and-`sessioned` rule used to sit. Behaviour is unchanged.
- **#513** Dropped two stale comments in `office.ex`: the description above `home_ws_ids/1` (it described `threads/5` and predates the idle-until-register rule) and the orphan warm-window line over `held_windows/1`. The one load-bearing line now sits above `desk?`.
- **#514** Office test: on a standing thread, the lead's own window reads `desk` only with its session registered on that thread. A session on another thread leaves the seat `idle`.

Not in this change: #237 (`pane_stuck`) is specced against the name later. `Coworker.status/1`'s `:cold` fallback still covers the window-only case by position, not by calling the predicate.

### How it was checked

- RED for #507: `coworker_status_test.exs` failed with `UndefinedFunctionError` for `window_only?/2` before the predicate existed.
- GREEN for #507: `office_test.exs` and `coworker_status_test.exs`, 28 tests, 0 failures.
- #513 is comments only. `office_test.exs` run after it: 23 tests, 0 failures.
- #514: passed on first run, so it was checked by mutation. With `desk? = live` (the window-only check removed), the new test fails (`"desk"` where `"idle"` was expected), and so does the existing "where its lead is" test. The mutation was reverted and both suites were green again: 29 tests, 0 failures.
- Server gate: `menard run check --in server`, see the commit status for its verdict.
