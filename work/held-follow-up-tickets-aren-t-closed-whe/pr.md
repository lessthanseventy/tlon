Intake closes tickets that main already fixed (#717)

Each intake pass first reads the newest 300 commits on origin/main; a backlog or routed ticket whose id ends a commit subject as `(#N)` is closed with the sha as evidence, so a released held follow-up another workline already fixed is not routed for a manager + tech-lead triage. Only the closing `(#N)` counts (a bare #N is often a PR/thread number, cf. #720). The git read is injected (`landed:`), passed only by `Server.Jobs.Intake`, so tests never read the real log.

Checked: `menard run test --in server test/server/intake_test.exs` — 28 tests, 0 failed (3 new: closes backlog, closes held, ignores non-closing #N); RED run first showed the 3 failing.
