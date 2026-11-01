APPROVE — #661 (re-review after rebase)

The branch's own diff against origin/main is unchanged: the 17-line test in `server/test/server/switchboard_test.exs`, plus pr.md. The 17-file delta since 9aaf321 is main's movement from the rebase, not this branch. No production code touched.

I checked the diff, not the suite. The builder reported 59 tests green and `mise run check` green on f99a783.

No findings, no follow-ups.