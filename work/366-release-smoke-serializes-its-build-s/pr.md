release-smoke.sh: build one at a time machine-wide, and name a pool failure (closes #366)

Two smokes (or a smoke and a gate) building at once starved Postgres of connections; the second died in
`Ecto.Migrator.lock_for_migrations` with only "the build or the migration … failed".

- Only the heavy step (deps.get, mix release, drop/create, migrate) now runs under a blocking flock,
  `tlon-smoke-build.lock` in the common git dir, printing "smoke: waiting for <holder>'s build". Built
  smokes, and holds, still run concurrently; the kernel frees the lock with a killed holder.
- A log tail holding `DBConnection.ConnectionError` or `too_many_connections` gives the verdict
  "Postgres ran out of connections during the migration … wait for it, then re-run".
- Pool size untouched; the smoke is not in the checks queue.

Checked: new scripts/release-smoke.test.sh (two fake builds serialize, waiter names the holder, SIGKILLed
holder frees the lock, verdict on both error strings, only the tail counts), wired into the server check
task. Not run: a real two-smoke build (needs unsandboxed Postgres); the original failing log was gone.
