APPROVE — 7011d86 (#559)

Source change is correct and minimal: `timeout(opts)` is computed once in `do_history` and passed to `details/3`, `with_window/3` and `count`; the two `Repo.query!` calls now carry `timeout:`. I read the diff and grepped search.ex. I did not run the tests (sandbox has no Postgres), so the author's "red on main, green with the change" is theirs, unverified by me.

Test review: the telemetry-triggered lock is clever but brittle.
- Details case depends on the `SELECT id, embedding` query actually running in the test env. If it doesn't, no holder starts, the `ts_headline` clause does `send(nil, :release)`, and the handler crashes and detaches silently. Author says it went red on main, so it evidently runs.
- Window case relies on `UNION ALL` appearing only in the window query (true today, search.ex lines 206-207).

Neither blocks. Follow-up below.