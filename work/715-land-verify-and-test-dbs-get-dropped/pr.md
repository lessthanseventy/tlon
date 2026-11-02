Land, verify and per-worktree test databases are dropped, not left behind. Closes #715 (the land/verify/test slices; the eval slice was #556).

- `scripts/workline-verify.sh`: the EXIT trap drops its own `tlon_<verify|land>_<slug>` database after the verdict is recorded. A failed drop prints a warning; the exit code (the gate's verdict) is untouched.
- `Server.Worktree.retire/2`: drops the checkout's `tlon_test_<name>_<hash>` database. `Server.TestDatabaseName` moves to `lib/server/` so retire and `config/test.exs` share one naming rule; only `tlon_test_*` names are ever dropped.
- `scripts/db-sweep.sh`: no argument now also sweeps `tlon_land_*`, `tlon_verify_*` and `tlon_test_*` slug names, with `tlon_test` and `tlon_test_main` excluded by name and the same idle check and double name check before DROP. An explicit prefix keeps its `<prefix><digits>` behaviour.

The existing databases are not swept by this change; clearing them is a separate call.

How checked: `workline_verify_script_test` (fake `psql`: dropped on green and red, verify and land names, failed drop keeps the exit code), `worktree_test` (retire drops its own db and not a neighbour), `db_sweep_script_test` (fake `psql` pins the name filter). Each written red first.
