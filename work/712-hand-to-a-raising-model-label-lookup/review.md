APPROVE

Right then. The change does what pr.md says and no more.

- `hand_to` (workline.ex:1511) now goes through a private `model_label/2` that rescues, logs, and returns nil. `Trust.leads_line/3` already takes nil, so the leads line posts bare and the new lead still gets its brief and wake. That was the bug: `assign_lead` had closed the old lead's window, then a raise skipped `post_brief`.
- The `:model_label` app-env seam copies the existing `:trust_record` seam in `with_trust/1` (workline.ex:2474), so it matches the file's idiom.
- Tests: the raising case asserts the lead is assigned and the body is exactly `→ lead leads (build stage)`. The nil case also checks `Trust.model_of/1` returns nil. Both clean up the env in `on_exit`.
- Not verified by me: I did not run the suite. The 94/0 figure is the builder's claim in pr.md.
- Scope is surgical: 12 lines in lib, tests, and pr.md. No docs went stale.

Follow-up, not blocking: `mcp/spawn.ex:178` and `workline/review.ex:19` call `Profiles.model_label/2` bare, with the same exposure.