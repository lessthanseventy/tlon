# Review — server-eval-drops-its-tlon-eval-pid-db-w @ 5c69807

**Verdict: APPROVE.** Both halves of #556 are in the diff and do what the tech lead asked (thread 443 msg 17704, points 1–3). No blocking finding. One follow-up (a false zero in the sweep's exit path).

## Checks read
- `mise run check` passed on 5c69807 (CHECKS row 2026-10-30T01:36:35Z, exit 0; server suite includes the five new tests). No `bench_contrast` row: the diff touches no persona file, so none is owed.

## Findings, numbered

1. **server.eval `try … after` is correct.** `Mix.Task.run` runs a task once per process, so the `Mix.Task.reenable("ecto.drop")` before the second drop is load-bearing, and it is there. `--force-drop` becomes `DROP DATABASE … WITH (FORCE)` run against the maintenance db (ecto_sql `postgres.ex` `storage_down/1`), which terminates the Repo pool's own connections after `app.start` — so the drop lands green, red (`Mix.raise` inside the body) or raised. A SIGKILL skips `after`; pr.md says so and hands that case to the sweep. An `after` that itself fails would replace the body's `Mix.Error` with its own — exit still nonzero, message changes; not worth code.

2. **Sweep scope is structurally safe.** The prefix must match `^tlon_[a-z0-9_]+$` and end in `_`, so no quote or regex metacharacter reaches the single-quoted SQL pattern or the double-quoted identifier in `DROP DATABASE IF EXISTS "$db"`; every name is re-matched against `^<prefix>[0-9]+$` in bash before DROP. `tlon`, `tlon_dev`, `tlon_test`, `tlon_test_main` cannot match a digits-only suffix. Tests cover `""`, `tlon`, `tlon_`, `x_`, `tlon_eval_%`, `tlon_eval_.*`, `a'b_` refused, and `x`/`999999x`/`x999999`/`_` suffixes untouched. The DROP deliberately has no `WITH (FORCE)`: a database that gained a connection between the list and the drop fails the drop and is kept. Good.

3. **False zero (follow-up, non-blocking).** `while read … done < <(pg -c "select …")`: when the listing query fails (Postgres unreachable, a sandboxed shell, wrong socket), the loop reads nothing and the script prints `db-sweep: dropped 0 tlon_eval_* database(s)` and exits 0 — the server rule's "a false zero reads exactly like a real zero". psql's stderr does show the error, so a hand run is not misled, but the exit code is. Patch in follow-ups.

4. **Liveness window (note, no action).** Between `ecto.create` returning and `ecto.migrate`'s first connection, nothing is connected to the fresh `tlon_eval_<pid>`; a sweep in that gap would drop it and the eval goes red on migrate. This is inherent to the `pg_stat_activity` design the tech lead specified, and the sweep is a hand-run task, not a schedule. Only matters if #715 schedules it.

5. **Test reads its own file (nit).** "no argument means tlon_eval_" asserts the script's text (`prefix="${1-tlon_eval_}"`) rather than running the default — server/AGENTS.md's "a test that reads our own files proves only that we were consistent". The default cannot be exercised without touching the live `tlon_eval_*` set, so this is the honest compromise. No change asked.

6. **Spec compliance.** (1) eval drops at end: yes, with evidence in pr.md (green and forced-red runs, no new db). (2) `server:db-sweep` over a script in smoke-sweep's shape, prefix argument default `tlon_eval_`, numeric-suffix-only, pg_stat_activity liveness, count printed: yes. (3) not run against the live box: the shipped code was not; emma's disclosed slip during development (msg 17709: a `${1:-}` default turned an empty test prefix into `tlon_eval_` and dropped 100 idle live databases, 992 → 892) is already on the thread, the cause is fixed (`${1-}`, an empty prefix refused, test covers it). The remaining 892 are the operator's call, per tertius. Not scheduled, as asked.

7. **Manual and task.** `docs/manual/tasks.md` regenerated (74 → 75 verbs); `manual:check` was the red on e36a809 and is green on 5c69807.