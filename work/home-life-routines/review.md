VERDICT: request_changes (one small fix; the rest is sound)

Reviewed by reading the diff (life.ex, routine/quest/run schemas, both migrations, MCP tools, OperatorAPI routes, schedules.ex additions) against spec.md. I did not re-run the suite; I rely on the recorded green `mise run check` (1134 tests, 0 failed).

## Must fix

1. **No range validation on `xp` / `window_minutes`, and `Life.level/1` has a `when xp >= 0` guard.** The Routine/Quest changesets only `cast` these. A quest or routine created via `quest_create`, `routine_create` or `POST /api/life/...` with a negative `xp` can push the workspace total below 0. After that `Life.status/2`, `routine_done` and `quest_done` raise FunctionClauseError, so the workspace's life endpoints stay broken until the row is edited. A negative `window_minutes` makes every run late.
   Fix: `validate_number(:xp, greater_than_or_equal_to: 0)` in both changesets (including `update_changeset`), and `validate_number(:window_minutes, greater_than_or_equal_to: 0)` on the routine changesets. Add one test that a negative xp is rejected.

## Follow-ups (not blocking)

2. **Double-stamp race.** `routine_done` is check-then-insert with no unique index on `(routine_id, due_at)`. The spec defers it (§8.4), but concurrent calls (a double click, or the card and an agent at once) double-count XP. A unique index plus mapping the constraint to `:already_done` closes it, as its own small step.
3. **`current_due_at` walks every occurrence from `created_at` on each call, and `streak` calls it once per step back.** That is O(n²) cron parses and local-time conversions. Fine for `@daily` over months; a minutely or hourly routine will make `status/2` slow within days. Later fix: start the walk from the latest run's `due_at`.
4. `create_routine` and `create_quest` don't check the workspace is `type: "home"` (spec §2.1 scopes them to home workspaces). `routine_done` also works on a disabled routine. Name these in the spec if intended.

## Checked and fine

- UTC/local handling: `next_occurrence` goes through `after_local` and returns real UTC. `Life.status` compares true instants and uses `Schedules.local_date` only for "today".
- Late rule (`> due + window`, boundary on time), half-XP integer division in SQL, level-up computed from xp before and after one write.
- Migrations: versions are past main's, the CHECK swap on `workspace_type` has a symmetrical `down`, FKs cascade.
- OperatorAPI: key whitelist means `String.to_existing_atom` can't be fed arbitrary input; routes sit before the `no_route` catch-all.
- `RoutineUpdate` returns `fail` rather than raising on an unknown id.

The operator gate applies on exit: this touches migrations and `server/AGENTS.md`.
