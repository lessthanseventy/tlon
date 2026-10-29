# Review: start-smoke-idempotency-on-the-resolved @ e6f9be0 (round 2)

**Verdict: request_changes.** Round 1's blocking finding is unfixed. The delta since 18573ea (`git diff 18573ea..e6f9be0 -- server`) fixes the two thread follow-ups (start's moved-tip wording, `building/2`'s @doc) and nothing else; the witness is the one line the finding named, unchanged:

```elixir
defp replace(old, thread_id, ref, sha, opts) do
  case stop(thread_id) do
```

## 1. `replace/5` still cancels *a* building job of the thread, not *the* one it found (blocking, round 1 §1)

`old` came from `building(thread_id, ref)`. `stop/1` re-queries `held(thread_id) || building(thread_id)`; with no ref, `building/1` is `order_by: j.id, limit: 1` across every ref the thread has queued. `start/5` refuses while a smoke is held, so `held` can't bite here; two refs can, and the suite's own "a start for another ref still queues" says two refs on one thread is allowed:

- job A (lower id) queued for `main`; job B queued for `work/x` at s1.
- tip of `work/x` moves to s2; `start(t, "work/x")`.
- `building(t, "work/x")` → B. `stop(t)` → `building(t)` → A. A is cancelled, `:ok`.
- a new job is inserted with `meta.replaced = B.id`. B still builds s1; A, which nobody touched, is gone; the MCP result says B was cancelled.

Round 2's new tests both run on one ref, so they pass by construction and don't reach this. Fix as round 1 gave it: stop the job you found, by lifting `stop/1`'s three job clauses into `stop_job/1`:

```elixir
def stop(thread_id) do
  case held(thread_id) || building(thread_id) do
    nil -> {:error, "no smoke is up for this thread"}
    job -> stop_job(job)
  end
end

defp stop_job(%{meta: %{"os_pid" => pid}}) when is_integer(pid) do
  _ = System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true)
  :ok
end

defp stop_job(%{state: state, id: id}) when state in ["available", "scheduled"], do: Oban.cancel_job(id)

defp stop_job(job),
  do: {:error, building_error(job, "its script has not started yet; stop again in a moment")}

defp replace(old, thread_id, ref, sha, opts) do
  case stop_job(old) do
    :ok -> insert(thread_id, ref, sha, opts, %{"replaced" => old.id})
    {:error, _} -> {:error, "the tip of #{ref} moved, but the old build (job #{old.id}) can't be cancelled until its script starts: start again in a moment"}
  end
end
```

The red-first test, beside "a start for a tip that moved cancels the queued build…": queue `"main"` then `"work/a-thing"`, move the resolver, start `"work/a-thing"` again; assert the `main` job is still `available`, the old `work/a-thing` job is `cancelled`, and `new.meta["replaced"]` is the old `work/a-thing` id. Round 2's "can't be cancelled yet" test stays green under `stop_job(old)` (executing, no pid → the error clause).

## Checked and sound this round

- Round-1 follow-up 2 fixed: `replace/5` now returns start's own words (tip moved, job N can't be cancelled until its script starts, start again); the new test asserts the words and refutes "stop again".
- Round-1 follow-up 3 fixed: `building/2` @doc says same commit / moved tip replaces.
- Round-1 follow-up 1 (the script re-resolves the ref at run time) dropped for #538–#540, as hronir settled; carried below so it isn't lost.
- Everything round 1 found sound is unchanged: resolve once at start in `main_root`'s git dir, sha in args, same sha returns the job, unresolvable ref refuses with nothing queued, script still takes the ref, `:smoke_resolve` knob cleaned up in test setup.
- CHECKS: `mise run check` green at 17:47Z on this branch. No `bench_contrast` row, as expected for a non-steering change.
