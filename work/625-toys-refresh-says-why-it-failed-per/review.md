APPROVE.

Read the full diff against origin/main. I did not re-run the gate. The PR reports `menard run check --in server` at 2487 tests, 0 failures, and I did not verify that.

- `ModelCli`: the exit-124 branch now keeps stderr via `why(err, out)`. A grep finds no other consumer of the old 2-tuple `{:model_cli_timeout, s}`. The judge test and the ModelCli test are updated, and a new test pins the stderr text.
- `ToyPool.run_jobs/4`: clause order is right. An empty list matches first, so a streak of 3 on the very last job reports no stop. Any non-timeout result resets the streak. The untried count is `length(jobs)` at the stop.
- `refresh_cli/0`: `fresh` counts `{:ok, _}`, which includes `refresh_due`'s already-fresh `{:ok, items}` and `GeneratedParts`' `{:ok, :fresh}`. `off` counts `{:error, :off}`. `bad` is the remainder, which matches the old rule. It raises on `bad > 0` or on a stop, so the old script's exit semantics are kept.
- Tests cover the all-fresh path and the hung-model path. The hung-model test checks 3 calls, the stderr text in the output, the stop line, the raise, and that the pool is left empty.
- The docs and the task description now name `refresh_cli`, and `tlon-cli.sh toys` is a single call.

Not verified:
- A run against the real Ollama service, as the PR itself says.
- Whether `IO.puts` through `rpc` streams to the caller as it happens. The old script printed through the same path, so at worst it behaves as before.

Residual risk: the 3-timeout streak stops only consecutive timeouts. Pools that are slow but still answer can run past 1800 s in aggregate. That is out of scope here.