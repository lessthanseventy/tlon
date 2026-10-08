VERDICT: approve

Re-review after request_changes. I read the delta `d88645f..HEAD` (6c9c36e, 2b7f8d2); I did not re-run the suite and rely on emma's reported green gate (1135 tests, 0 failed) and the server's verify.

## Must-fix: resolved
- `validate_number(:xp, >= 0)` on Quest create and Routine create/update; `window_minutes >= 0` on Routine create/update. This is exactly the patch asked for.
- Test covers negative xp (quest, routine create, routine update) and negative window_minutes.

## Still open (non-blocking, from the prior review)
2. Double-stamp race: no unique index on `(routine_id, due_at)`; spec defers it (§8.4).
3. `current_due_at` / `streak` are O(n²) for high-frequency routines.
4. `create_routine`/`create_quest` don't check the workspace is `type: "home"`; `routine_done` works on a disabled routine.

The operator gate applies on exit (migrations, `server/AGENTS.md`).