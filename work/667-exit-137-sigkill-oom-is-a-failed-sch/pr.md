Exit 137 (SIGKILL, which is also the kernel OOM killer) is a failed scheduled run again, not "interrupted".

Why: a nightly `check:main` that ran out of memory read as interrupted, so no sheriff page and `release:status` showed no why. A stop or release restart sends SIGTERM (143), which since #360 covers #312 alone. `@interrupted_exits` is now `[143]`.

Tradeoff: a `server:stop` that escalates to SIGKILL after its grace period now pages the sheriff. That is the operator's call.

Closes #667.

Checked: new test in `schedules_test.exs` (exit 137 closes failed, sheriff beat opened) fails without the change and passes with it; `menard run test test/server/schedules_test.exs` green, 21 tests.
