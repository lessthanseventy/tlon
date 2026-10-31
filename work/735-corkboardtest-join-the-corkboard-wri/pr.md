Fix the corkboard test's teardown race (#735).

Corkboard note writers run the test's fake model via `System.cmd` on `Server.TaskSupervisor`, and
were still running when `on_exit` removed the tmp dir (`cat >> prompts` landing mid-`rm_rf` → `:eexist`).
Corkboard now takes a `task_supervisor:` start option (default `Server.TaskSupervisor`); the tests run
their own unlinked `Task.Supervisor`, and `on_exit` waits (bounded, loud on timeout) for it to be idle,
stops it, then `File.rm_rf!`s the dir. Env resets happen after the join so a late writer never reaches
the real model. A pin test has the fake model recreate `prompts` for ~0.5s with the test ending at once:
red with `:eexist` before the join, green after.

Checked: `menard run test` corkboard_test ×4 green; `menard run check --in server`: 2527 tests, 0 failed.
