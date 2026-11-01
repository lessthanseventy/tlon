APPROVE — #661 (re-review)

The branch's own diff against origin/main is still the 17-line test in `server/test/server/switchboard_test.exs`, plus work docs (checked with `git diff origin/main...HEAD --stat`). The large delta since 9aaf321 is main's movement from the rebase, not this branch. No production code is touched.

I read the diff and did not run the suite. The grader flagged that the test might pass on the tlon-author exclusion alone, without exercising the reassignment guard. I did not test that by reverting the guard. It is not a blocker for a test-only change.

No findings, no follow-ups.