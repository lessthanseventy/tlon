# Review — facts about code carry a recheck (#88), round 2

**Verdict: approve.** I read the diff and tests; I did not run the suite myself. The server's verify recorded `mise run check` green on this branch.

## Round-1 findings, resolved
1. **Batch starvation.** `sweep_fact_rechecks` walks all live candidates, least recently checked first. It spends the 25-fact budget only on facts that got a verdict, so prose and ref-less facts no longer fill the batch. `CodeRefs` stays the single rule source. A test covers 30 prose facts plus 1 code fact.
2. **Probe prefix false-passes.** Module and function probes use `git grep -E` with an escaped name and a trailing boundary. Tests cover prefix misses (`Server`, `g`, `g?`) and a flag-like needle (`-v`).
3. **Minor.** The silent rescue now does `Logger.warning` with the fact id. The weak `:function` ref is documented in the `CodeRefs` moduledoc.

## Checked, no issue
- Probes are argv-only (`System.cmd("git", …)`, no shell), and the fact's own `check_cmd` is never run.
- Event correlation is `fact:<id>`, which is what `Strength` weighs. The 24h window and the `server recheck: ` detail prefix keep rechecks idempotent and distinguishable from real `check_cmd` results.
- Forgotten, superseded and thread-less facts are excluded. The `NOT IN` subquery is null-safe.

## Residual (not blocking)
- The candidate query loads every live fact each sweep (about 720 today). Add a limit or stream it if the store grows by an order of magnitude.
- The absence filter (`never`, `without`, `missing`, …) is conservative and skips some rechecks that would be valid. That is the safe direction.
