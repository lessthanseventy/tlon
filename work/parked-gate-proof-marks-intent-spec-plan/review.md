APPROVE. No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5).

Right then. `entry_stage/1` now reads the earliest `stage_advanced` and takes `coalesce(from, to)`. A promotion's opening event has no `from`, so its `to` is the entry. Any other first advance left the entry stage, so its `from` is the entry. With no events at all the entry is `thread.stage` instead of the hard-coded "intent". Only `promote/1` writes an opening event, so a workline opened at build or review used to be charged for stages it never owed, and this fixes that.

Checked:
- `menard run test` on `workline_proof_test.exs` gave `{"ok":true,"tests":5,"failed":0}`.
- The new tests cover three cases: opened at build with later advances, opened at review and never moved, and the existing full-proof case with an explicit opening advance.
- The parked-gate test now says `refute notice =~ "plan"` and asserts the exact no-branch diff line, which matches the new behaviour.
- The diff touches only `workline.ex` and the proof test, plus `pr.md`. No migration, dependency or gate change.

I did not run the full gate; verify does.