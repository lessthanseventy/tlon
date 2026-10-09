APPROVE — builder-senior suite from real worklines.

Verified by reading the diff (I did not re-run the gate or --oracle; the thread's verify evidence shows `mise run check` green and emma reports --oracle ✓ on all six):
- `source.commit` in task.json is validated (7–40 hex); `seed_source` uses `git archive <sha>^ server`, so the model sees no future history (fresh one-commit fixture repo). Hidden check files are copied over after the work, as for repo fixtures.
- `--oracle` applies the real diff minus `server/test` and grades; it fails on an empty set, so it can't pass vacuously. It spends no quota and writes no results.
- builder-senior now maps to the `senior` set; junior keeps `builder`. The `!!(task.repo || task.source)` change only widens the builder-style argv to sourced tasks.
- Sourced checks get a 900s timeout; docs (server/AGENTS.md, tasks.md, bench.toml description) updated in the same change. Seed tests cover seed_source, reference_patch, apply_reference.

Notes (non-blocking):
1. `seed_source` copies the live `server/_build` and `deps`, so fixtures depend on the host's build matching the parent's mix.lock; s6 was swapped for that reason. A new fixture whose parent predates a deps bump fails at the check — `--oracle` catches that before quota is spent.
2. The reference patch excludes all of `server/test`; a workline that adds test support files makes the oracle red (loud, not silent), so acceptable.
3. Sonnet 5.5 scores 3/6 on the full suite, so the set separates models. The deepseek-flash run is not in the commits I saw; the ticket asked for the Sonnet vs flash table, so report it on the thread if it exists.