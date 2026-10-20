# Orphans: a restart's exhausted job is discarded, not requeued

Closes #417 (hronir's diagnosis on the lobby, #8940); closes the `running`-forever half of #312.

At boot `Server.Jobs.Orphans.requeue` put every job this node left `executing` back to `available`
without looking at `attempt`. A job already at `max_attempts` is never run that way: Oban's Basic
fetch picks a queue's oldest available jobs first (LIMIT = free slots) and only then drops those at
their limit, so an exhausted orphan is picked every time and holds its slot. Two of them (the gate
and smoke runs at the 10-14 01:15 restart) stalled the `schedules` queue for a week; the `default`
queue carried the same pair since 10-10 and ran on 3 of its 5 slots.

Now Orphans follows Lifeline's rule: below `max_attempts` → `available`; at it → `discarded`
(`discarded_at` set), logged as a warning. A discarded `RunSchedule` closes its `schedule_run` row
as `failed` with `interrupted: the server restarted before the run finished`, so the automation
board never shows it `running`. An interrupted run prints no `ran-on` line, so it carries no `sha`
and `Server.Release.Candidate` never reads it as a verdict.

Not in this PR: the live db. The four exhausted jobs and the week's backlog are the operator's
decision (#8937). Nothing else describes Orphans (AGENTS.md names only `Server.Orphans`, the
process one), so no doc moved.

Checked: `server/test/server/jobs/orphans_test.exs` grew three tests that went red first — an
orphan at its last attempt is discarded and one below it requeued; the engine's own fetch for
`schedules` (limit 2) returns the real run behind two exhausted orphans; the discarded run's row is
closed as interrupted. `mix precommit` on the branch: credo clean, 1883/1884 — the one failure is
the #416 flake (`check_main_script_test.exs:78`, a TERM mid-gate under load), which passes alone;
the earlier `mise run server:check` run on the same tree was green through the deterministic eval.
