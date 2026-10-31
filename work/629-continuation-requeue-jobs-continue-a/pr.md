Continuation: a nudge skipped inside `continuation_gap_minutes` is requeued for the gap's end

`Continuation.run` skipped a nudge inside the gap of the last nudge or the lead's last post, but nothing queued the check again. The withheld nudge waited for the Maintain quiet sweep, up to an hour, not the 10-minute gap. The skip now returns the gap's end (the later of the two, plus the gap) and enqueues `Jobs.Continue` with `scheduled_at` there.

Closes ticket #629. Not built: the gap measured across a stage advance.

Checked: `menard run test --in server` on `maintain_test` and `workline_continuation_test` gives 48 tests, 0 failed; the full server check gives 2496, 0 failed. The requeue test was red first, with no job enqueued. Two regression tests are added: a lead's post holds nudges back for one gap only (injected `now:`), and the quiet sweep still nudges a workline silent for 2h at the default gap.
