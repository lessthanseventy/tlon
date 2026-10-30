# restart-resume wakes only sessions begun before this node booted

Closes #580. `Staffing.resume_interrupted` re-woke a mid-turn, windowless session every minute: the session each wake spawned was itself windowless and mid-turn, so the next pass ended it and woke again.

`Staff.interrupted/2` now lists only sessions with `started_at` before the node's boot (`Staff.mark_boot/1`, a `:persistent_term` set once in `Application.start`), so one restart yields one wake. Not tmux's clock: a `server:restart` can leave tmux up. What happens to a genuinely windowless post-boot session stays with `end_windowless` / #566.

Checked: `menard run test server/test/server/staffing_test.exs` — 46 tests, 0 failures, including two new ones (pre-boot session woken once and its successor left alone; post-boot session never ended).
