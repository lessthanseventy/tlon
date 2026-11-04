# Review: 715-land-verify-and-test-dbs-get-dropped @ 299ad3c

**Verdict: request_changes** — one finding, three lines to fix. The three pieces the ticket asked for are built and tested as asked; the fix for the compile warning weakens the gate that runs on them.

## 1. `config/test.exs` leaves `ignore_module_conflict` on for the whole test compile (blocking)

The witness, 299ad3c:

```
+# (the compile that follows defines the module again, so the option stays on: no conflict worth a warning)
+Code.put_compiler_option(:ignore_module_conflict, true)
+Code.eval_file(Path.join(__DIR__, "../lib/server/test_database_name.ex"))
```

`mix precommit` runs in `:test` (`mix.exs`: `preferred_envs: [precommit: :test]`), so its `compile --warnings-as-errors` is this compile. With the option on, *every* "redefining module" warning in `lib/` and `test/support` is silenced, not just this one: two files defining the same module would now pass the gate. The comment says "no conflict worth a warning"; the option does not know which conflict it is suppressing.

The cause is the eval'd module staying in memory when `lib/` compiles. Remove it after it has answered, and the option can go:

```elixir
Code.compiler_options(ignore_module_conflict: true)
Code.eval_file(Path.join(__DIR__, "../lib/server/test_database_name.ex"))
test_database = Server.TestDatabaseName.compute(__DIR__, System.get_env("TLON_TEST_DATABASE"))
# the module is compiled again from lib/ below: gone from memory, there is no conflict to warn about
:code.purge(Server.TestDatabaseName)
:code.delete(Server.TestDatabaseName)
Code.compiler_options(ignore_module_conflict: false)
```

Verified the mechanism outside the repo (`elixir run.exs`, OTP via mise): eval_file + purge/delete, then `Code.compile_file` of the same file → no warning; the same compile without the purge → `warning: redefining module … (current version defined in memory)`. Check it the way emma did: `MIX_ENV=test mix compile --force --warnings-as-errors`, then the suite.

## Read and found sound

2. **`scripts/workline-verify.sh`** — `db` is fixed before `trap cleanup EXIT`, so every exit after the trap drops `tlon_<verify|land>_<slug>` and only that; the two early `exit 1`s and the `flock -n … exit 0` skip come before the trap, so a skipped duplicate never drops the running one's database. `WITH (FORCE)` is right for an own-run drop. The `||` keeps the verdict's exit code; `workline_verify_script_test` pins green, red, verify, land and the failed drop.
3. **`Server.Worktree.retire/2`** — the name is computed before `worktree remove` (the walk-up needs the `.git` file), from the same `<wt>/server/config` string config/test.exs sees as `__DIR__`, so the hash agrees. `drop_test_database/1` matches only `"tlon_test_" <> rest` with a closed charset; a menard worktree gets a harmless `DROP … IF EXISTS` of a name that never existed. Taking `socket_dir`/`hostname`/… from `Server.Repo.config()` rather than its `url` is the right pick: the suite's database lives where the test env's config puts it, not where the service's URL points.
4. **`scripts/db-sweep.sh`** — the no-argument pattern `^(tlon_eval_[0-9]+|tlon_(land|verify|test)_[a-z0-9_]+)$` cannot match `tlon`, `tlon_dev` or `tlon_test`; `tlon_test_main` is excluded in the SQL and again before DROP, the same double check the eval sweep had. The explicit-prefix mode is unchanged. The fake-psql test pins 14 kept names against 5 dropped, including case, `;` and `"` in a name.
5. **Scope** — nothing here sweeps or drops an existing database; the worktree test creates its own two `tlon_test_dbdrop_<hash>*` names and drops them in `on_exit`. CHECKS: `mise run check` green on 299ad3c (in a train with #525); no `bench_contrast` row, so nothing to contrast.