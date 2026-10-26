# QA no longer takes the lead at a re-entered review off last round's approval

Closes #665.

`Workline.advance`'s `hand_to_qa` judged review.md's first line, which stays on the branch across
rounds. After a send-back, the next review saw the previous round's "approve" and seated QA before the
reviewer had filed anything, stranding the reviewer off-thread. It now hands off only when this round has
a verdict or no earlier round did (the same rule `this_round` already applies to `submit_review`).

Checked: new test in `workline_qa_test.exs` was red (advance returned `{:ok, _}` and QA took the lead),
now green; `menard run test test/server/workline_test.exs test/server/workline_qa_test.exs` 87 tests, 0 failures.
