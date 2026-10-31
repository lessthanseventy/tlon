APPROVE. No free reviewer at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5), so weigh accordingly.

Verified: `menard run test --in server` on arbiter_tmux_test + staffing_test → ok, 69 tests, 0 failed. Read the full diff. I did not run the full gate (verify does).

What it does
- `Arbiter.Tmux.spawn` now takes `:global.trans({{Tmux, ws, window}, self()}, …)`, and tmux is listed inside the lock. A second concurrent wake sees the first's window and gets `:already_running`. The body moved to `open/6` unchanged; the `else` clauses still cover `{:error,_}` and the nil workspace. The concurrency test is real (slow fake list-windows, two Tasks, exactly one new-window).
- `Staff.stranded/3` plus `resume_interrupted` now also sweeps a mid-turn session begun since boot, windowless and quiet past `@boot_grace_s` (600s). `mid_turn/1` is a clean extraction. A NULL `last_active_at` is never swept, which is the safe side. The test covers a live leaf (left alone), a dead pane (ended and told once), and a fresh session inside the grace (left alone).

Notes, not blockers
- The sweep trusts `has_window?` tagging. If a live pane's window is mistagged and the pane has been silent more than 10 minutes (a long Bash with no server call), it gets ended and told to pick up. The grace bounds this and the pane's next call re-seats it. Accepted trade-off.
- `:global.trans` retries forever by default. The critical section is a few tmux calls, so this is fine. A wedged tmux would queue spawns behind it. Worth a timeout only if that is ever seen.