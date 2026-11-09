# Hold a parked review gate's Uqbar route while its grade job is live

Closes #744. Under an `auto_land_risk` standing approval, a review gate is `held` (in no group, so
`NeedsPage` pages nobody) while its thread's `Server.Jobs.Grade` job is available, scheduled,
executing or retrying. The hold ends on its own when the job ends; a gate still waiting then routes to
Uqbar with its `uqbar_route_minutes` clock starting at the job's end, not the park. No Grade job, or no
standing approval: unchanged.

Checked: three new routing tests (live job routes nowhere; done job routes to uqbar with `at` from the
grade; no job routes at once) plus one for no standing approval; red before, `menard run test` on
needs_test.exs green (107 tests).
