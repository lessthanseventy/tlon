Office: `status()` passes `ticket_week` through, so `weekTrend` reads live data.

`/office` sends `ticket_week`, but the whitelist in `office/tui/data.ts` `status()` dropped it, so `weekTrend()` in `office/kit/crew.ts` always read empty on a live server. The fix is one field beside `ticket_open`, the same miss fixed in 820e739.

Closes #688.

Checked: test-first. `office/test/data.test.ts` now asserts `ticket_week`; it failed red with `undefined` before the whitelist change. `bun test` in `office/` passes (967 tests, 0 fail), and `tsc --noEmit` exits 0.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
