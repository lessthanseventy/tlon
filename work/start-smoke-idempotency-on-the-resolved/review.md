# Review: start-smoke-idempotency-on-the-resolved @ 95722bc

**Verdict: request_changes.** One correctness defect in the lines this change adds; the rest of the change does what #537 and hronir's read (thread 1, #17456) asked.

## 1. `replace/5` cancels *a* building job of the thread, not *the* one it found (blocking)

The witness, `server/lib/server/smoke.ex`:

```elixir
old -> replace(old, thread_id, ref, sha, opts)
…
defp replace(old, thread_id, ref, sha, opts) do
  with :ok <- stop(thread_id), do: insert(thread_id, ref, sha, opts, %{"replaced" => old.id})
end
```

`old` came from `building(thread_id, ref)`. `stop/1` re-queries with `held(thread_id) || building(thread_id)`, and `building/1` with no ref is `order_by: j.id, limit: 1` across every ref the thread has queued. The suite's own "a start for another ref still queues" test says two refs can build side by side on one thread, so:

- Job A (id 1) queued for `main`, job B (id 2) queued for `work/x` at sha s1.
- Tip of `work/x` moves to s2; `start(t, "work/x")`.
- `building(t, "work/x")` returns B. `stop(t)` finds A, cancels A, returns `:ok`.
- A new job is inserted with `meta.replaced = B.id`. B still builds s1; A, the build nobody touched, is gone. The MCP result tells QA that B was cancelled.

Fix: stop the job you found. The job-targeted half of `stop/1` already exists as its three clauses; lift it out so both doors use it.

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
    with :ok <- stop_job(old), do: insert(thread_id, ref, sha, opts, %{"replaced" => old.id})
  end
```

And the test that goes red first, beside "a start for a tip that moved…": queue `"main"` then `"work/a-thing"`, move the resolver, start `"work/a-thing"` again; assert the `main` job is still `available`, the old `work/a-thing` job is `cancelled`, and `new.meta["replaced"]` is the old `work/a-thing` id.

## What I checked and found sound

- Resolve happens once, at start, in `Server.Profiles.main_root/0`'s git dir with the script's own line (`rev-parse -q --verify <ref>^{commit}`); no fetch in the request path. The `@ref` grammar forbids a leading `-`, so the ref can't be read as an option.
- Sha stored in args beside the ref; same ref + same sha returns the building job; unresolvable ref refuses with `no commit <ref>` and queues nothing. Tests cover all three, red first per pr.md.
- The script still takes the ref, so the smoke node is untouched.
- `:smoke_resolve` knob mirrors `:smoke_script`; test setup cleans it up.
- `menard run check --in server` and `mise run check` green in CHECKS (2426 server tests). No `bench_contrast` row, as expected for a non-steering change.
