A raising `Profiles.model_label/2` no longer drops a handoff's leads line.

`hand_to` called the model lookup unguarded, after `assign_lead` had closed the old lead's window. A raise there skipped `post_brief`, so the new lead got no wake and the build never entered Trust's record. The lookup now runs through `model_label/2` in `workline.ex`: a failure logs and posts the leads line without the `[model: …]` suffix, the same rescue-to-neutral shape as `with_trust/1`. `Trust.leads_line/3` already takes nil.

Closes #712. Checked: `workline_test.exs` gained two tests. The raising case (via the `:model_label` seam) was red on `hand_to` (the brief never posted), now green; the nil case posts the bare `→ name leads (build stage)` and `Trust.model_of/1` returns nil. `menard run test --in server test/server/workline_test.exs`: 94 tests, 0 failures.
