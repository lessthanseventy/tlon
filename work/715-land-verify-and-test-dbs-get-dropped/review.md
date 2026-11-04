# Review: 715-land-verify-and-test-dbs-get-dropped @ e559b65

**Verdict: approve** — the one blocking finding carried through two rounds is fixed; nothing else changed.

## 1. `config/test.exs` no longer leaves `ignore_module_conflict` on for the test compile (fixed)

The witness, `git diff fb82100..e559b65 -- server/config/test.exs`:

```
-Code.put_compiler_option(:ignore_module_conflict, true)
+Code.compiler_options(ignore_module_conflict: true)
 Code.eval_file(Path.join(__DIR__, "../lib/server/test_database_name.ex"))
 test_database = Server.TestDatabaseName.compute(__DIR__, System.get_env("TLON_TEST_DATABASE"))
+# the module is compiled again from lib/ below: gone from memory, there is no conflict to warn about
+:code.purge(Server.TestDatabaseName)
+:code.delete(Server.TestDatabaseName)
+Code.compiler_options(ignore_module_conflict: false)
```

Line for line the snippet from the review at 0fdcbca. The eval'd module is gone from memory before `lib/` compiles, so the option is off again for the whole gate: a genuine "redefining module" in `lib/` or `test/support` fails `--warnings-as-errors` as it did before this branch. `:code.purge`/`:code.delete` return `false` rather than raise when there is nothing to remove, so the config file cannot fail on them. Evidence it builds: verify's `mise run check` green on the branch rebased onto main (CHECKS 02:36:30Z, `0 fail` across the server, adapters and office suites), and emma's `MIX_ENV=test mix compile --force --warnings-as-errors` clean with the test_database_name and worktree tests passing (69, 0 failures). I did not re-run the compile myself.

## Unchanged since fb82100, still sound

2. `scripts/workline-verify.sh`, `Server.Worktree.retire/2` (with the fail-fast timeouts from 0fdcbca), `scripts/db-sweep.sh` — see the reviews at 299ad3c and 0fdcbca; `git diff fb82100..e559b65 --stat` touches only `server/config/test.exs`.
3. CHECKS: `tlon/check` not posted (gh had no commit for the rebased sha 7665ff4), a server matter, not this change's. `bench_contrast` reads *unmeasurable* (server/AGENTS.md is read by a seat, not the bench): not a regression, nothing to contrast.

No follow-ups: the one from the first round (retire's drop hanging on a down Postgres) landed as 0fdcbca.