APPROVE — #667

- `@interrupted_exits` goes from `[143, 137]` to `[143]` (`server/lib/server/schedules.ex:30`). I read the diff and the other uses of the attribute in `schedules.ex`. Exit 137 now takes the failed path, so the standing note says failed and `Sheriff.report` fires. A stop or release restart sends SIGTERM (143), so #312's case is unchanged.
- The new test in `schedules_test.exs` runs `exit 137` and asserts `status: "failed"`, `exit: 137` and the sheriff beat thread. It covers the change. I did not run it myself; the PR text says 21 tests green and that the test fails without the change.
- No other code or docs reference 137 or `@interrupted_exits`. The #312 workline files under `work/312-*` still say 143/137, but they are historical records, so I left them alone.
- The tradeoff is stated in the PR: a `server:stop` that escalates to SIGKILL now pages the sheriff. I accept that, because an OOM kill should not be silent.
- I have no blocking findings.