keep_up: skip repos with no GitHub remote; one rollout note per unreadable repo

Closes #613. keep_up filed a rollout item per `gh` read per pass for a repo with no origin or one GitHub can't resolve.

- A repo whose origin is missing or not on github.com is skipped, said once in the log.
- A repo whose reads fail keeps one keyed note, cleared only when both reads of a pass succeed (a failed read is no longer wiped by the other read's success).

Checked: `menard run test` keep_up_test 19/19 (new tests red first); `menard run check --in server` 2073 tests, 0 failed.
