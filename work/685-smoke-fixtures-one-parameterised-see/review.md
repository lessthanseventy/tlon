No free reviewer is at the builder's grade (greybeard); tzinacan (deepseek-flash) reviewed.

Verdict: approve. Read-only review of `git diff origin/main...HEAD`; I did not run the suite (verify and the landing gate do).

Checked:
- `Smoke.start` accepts a spec `name` or `name:k=v,k=v`, and `Fixtures.parse` uses the same grammar. There are no spaces, so it survives the space-split `TLON_SMOKE_FIXTURES`.
- Unknown params are refused against each catalog entry's defaults; the tlon_smoke_* db guard is untouched.
- The hooks the fixtures lean on exist: `:health_reading` (Needs), `:operator_config_path` (OperatorConfig.path), `Life.current_due_at/previous_due_at/routine_done`, `Needs.settle/pass_up`, `Schedules.local_now`.
- `life_routine_overdue` is built from the local clock minus 5 minutes, so it does not depend on the time of day.
- Docs are updated in the same change (server/AGENTS.md, Profiles brief, StartSmoke tool description).

Non-blocking: the fixture-spec regex is written twice (`Server.Smoke` @fixture and `Server.Smoke.Fixtures` @fixture) and can drift. See follow_ups.