server.eval drops its database when the run ends; `server:db-sweep` clears the ones already left behind. Closes #556 (the eval slice of #715).

- `mix server.eval`: the run sits in `try … after ecto.drop`, so a green, red or raised eval drops its `tlon_eval_<pid>`. The drop at the start never found it: the pid is fresh each run.
- `scripts/db-sweep.sh` + `mise run server:db-sweep [-- prefix]`: drops `^<prefix>[0-9]+$` databases with no row in `pg_stat_activity` and prints the count. Default prefix `tlon_eval_`; a prefix not shaped `tlon_…_` (including an empty one) is refused, so `tlon`, `tlon_dev`, `tlon_test`, `tlon_test_main` are out of reach. Not scheduled.

How checked: `server/test/server/db_sweep_script_test.exs` (5 tests, red first, each in its own prefix: idle dropped, connected kept, `x`/`999999x`/`x999999`/`_` suffixes untouched, bad prefixes refused). Eval: `psql` listing of `tlon_eval_*` before/after a green `mix server.eval --deterministic` and a forced-red one (exit 1): no new database in either; before the change a green run left one.

NOT run against the live box's existing `tlon_eval_*` databases: that is the operator's call. (During development an empty-prefix bug in a test run swept 100 of them, 992 → 892; fixed, covered by a test.)
