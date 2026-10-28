A drift ticket's changed count is now said on the lobby (closes #467).

`KeepUp.drifted/2` updated an existing drift ticket's count silently, so the lobby's only line kept the first, stale count. When the count changes it now posts a notice (wakes nobody) with the new count; an unchanged count posts nothing.

Checked: `menard run test test/server/jobs/keep_up_test.exs` — 23 tests, 0 failures (changed-count test red first, plus an unchanged-count test).
