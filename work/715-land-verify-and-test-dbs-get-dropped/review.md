# Review: 715-land-verify-and-test-dbs-get-dropped @ 0fdcbca

**Verdict: request_changes** — the one blocking finding from the review at 299ad3c is still in the diff. The round's only code change (0fdcbca) is the non-blocking follow-up, done well.

## 1. `config/test.exs` still leaves `ignore_module_conflict` on for the whole test compile (blocking, unfixed)

The witness, `git diff origin/main...0fdcbca -- server/config/test.exs`:

```
+# (the compile that follows defines the module again, so the option stays on: no conflict worth a warning)
+Code.put_compiler_option(:ignore_module_conflict, true)
+Code.eval_file(Path.join(__DIR__, "../lib/server/test_database_name.ex"))
```

Nothing after it turns the option off. `mix precommit` runs in `:test`, so its `compile --warnings-as-errors` is this compile, and *every* "redefining module" warning in `lib/` and `test/support` is silenced for the gate, not just this one — two files defining the same module now pass. The fix is the same three lines as last round: purge the eval'd module once it has answered, then switch the option back.

```elixir
Code.compiler_options(ignore_module_conflict: true)
Code.eval_file(Path.join(__DIR__, "../lib/server/test_database_name.ex"))
test_database = Server.TestDatabaseName.compute(__DIR__, System.get_env("TLON_TEST_DATABASE"))
# the module is compiled again from lib/ below: gone from memory, there is no conflict to warn about
:code.purge(Server.TestDatabaseName)
:code.delete(Server.TestDatabaseName)
Code.compiler_options(ignore_module_conflict: false)
```

Mechanism verified last round outside the repo (eval_file + purge/delete, then a compile of the same file → no warning; without the purge → `redefining module … (current version defined in memory)`). Check it as before: `MIX_ENV=test mix compile --force --warnings-as-errors`, then the suite. The thread shows why it was missed: the back-to-build post relayed only the follow-up list; the blocking finding lives in review.md.

## 2. 0fdcbca — the follow-up, read and found sound

`connect_timeout: 3_000` on the start_link and `timeout: 10_000` on the `query!`. The bound that actually bites on a down Postgres is the query's 10 s (DBConnection's checkout wait); `connect_timeout` only caps a hanging TCP connect, and a missing socket fails at once. So "fails in seconds" means ~10 s, down from 15 — modest, and correct. Not using `backoff_type: :stop` was the right call: the conn is linked to the caller, so a stopped conn would exit retire's process past the `rescue`. The down-Postgres path has no test, as emma said; it needs an unreachable Postgres, and the warning path is the same `rescue` the suite already exercises through the query.

## Unchanged since 299ad3c, still sound

3. `scripts/workline-verify.sh`, `Server.Worktree.retire/2`, `scripts/db-sweep.sh` — see the review at 299ad3c, findings 2–5; no line of them changed.
4. CHECKS: `mise run check` green on the verify's rebased sha (`tlon/check` not posted — gh had no commit for that sha, a server matter, not this change's). `bench_contrast` row reads *unmeasurable* (server/AGENTS.md is read by a seat, not the bench): not a regression, nothing to contrast.