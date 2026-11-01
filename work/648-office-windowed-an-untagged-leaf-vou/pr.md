Closes #648.

Office's board (`Office.windowed?/3`) counted an untagged leaf window for any agent on its thread, so a former lead's session still on the thread read as at a desk. Staffing already applied #362's rule. Both now share one predicate, `Office.leaf_for?/4`, which holds that rule: an untagged leaf vouches for the thread's lead only. Both `own?` clauses are unchanged, since they differ on purpose.

The wake narrows on purpose: `Wake.seated?` goes through `Office.windowed?/3`, so an untagged leaf pane now seats only the thread's lead. The only new case is a thread with no stage, where a non-lead sits in a hand-made window.

Checked:
- RED first: `office_test` (untagged leaf vouches for the lead, not `borges`) and `wake_test` (a non-lead's wake in an untagged pane is let go, not paged). Both failed for the right reason before the change.
- GREEN: office, wake and staffing tests, 87 tests, 0 failures (`menard run test --in server`).
- Full server gate via `run_task server:check` on the committed head.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
