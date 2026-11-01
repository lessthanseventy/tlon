Cover the #251 lead-change case in the switchboard's "wake nobody heard" block.

A tlon stage notice names no addressee, so `redeliver_unheard/0` must not hand it back to whoever leads the thread now, even after a reassignment. The existing test only covered a notice on a thread with its original lead. The new test reassigns the lead with `Staff.assign`, ages the notice 12 minutes with the new lead's session silent, then asserts the new lead is not woken and `delivered_at` is untouched.

No production code changes. The test passed on its first run, so it pins existing behaviour rather than driving a fix. To check it can fail, I broke the tlon-author guard in `switchboard.ex`: the new test and its sibling both went red. The guard was restored before commit.

Closes #661.

Checked: `menard run test --in server test/server/switchboard_test.exs` gives 59 tests, 0 failures. `menard run check --in server` gives 2536 tests, 0 failures, exit 0.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
