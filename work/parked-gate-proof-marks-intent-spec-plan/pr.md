# Parked-gate proof: a stage before the one the workline opened at owes nothing, whichever door opened it

Closes #690.

The review gate's proof already skipped the stages before a workline's entry stage, but it read that
stage from a `stage_advanced` event with `from: null`, and only `Workline.promote` (the ticket path)
writes one. `Workline.open` at build (`staff_child`, the `build` verb) writes none, so `entry_stage`
fell back to "intent" and the operator read ✗ intent, ✗ spec, ✗ plan beside a green build and review.
The live db confirmed it: worklines 402, 407, 428, 434 and 437 carry no opening event and their first
event is build→verify.

`entry_stage` now reads the earliest `stage_advanced` event: its `from` when it has one (the first
advance left the entry stage), else its `to` (a promotion's opening event), else the stage the
workline stands at (one that never moved was opened where it is). Old and new worklines read right.

Checked: `menard run test --in server test/server/workline_proof_test.exs` — two new tests red
before (five proof rows), green after; `run_task server:check` on the committed head.
