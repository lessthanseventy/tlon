Verdict: request_changes. No free reviewer is at the builder's grade (senior), so this review was done by ulrikke at review grade, read-only, not re-run.

**Blocker: the quiet-band nudge is lost when the check is requeued.** `Continuation.run/2`'s `{:later, at}` branch requeues `Jobs.Continue` with args `%{thread_id}` only. `Jobs.Continue.perform/1` then calls `run(tid)` without `quiet:`. The quiet sweep (`maintain/sweep.ex` `sweep_quiet`) calls `run(t.id, quiet: true)`, and the "artifact there, nobody advanced it" nudge exists only under `opts[:quiet]` (`nudge/2`, otherwise `:nothing`). So a gap-held quiet nudge comes back as a plain check that posts nothing at the gap's end. The PR's claim that the nudge is "late, not lost" does not hold for this path, and no new test covers it.

Fix:
```
continuation.ex
- {:later, at} -> requeue(thread_id, at)
+ {:later, at} -> requeue(thread_id, at, opts[:quiet])
- defp requeue(thread_id, at) do
-   Jobs.enqueue(Jobs.Continue.new(%{thread_id: thread_id}, scheduled_at: at))
+ defp requeue(thread_id, at, quiet) do
+   Jobs.enqueue(Jobs.Continue.new(%{thread_id: thread_id, quiet: quiet == true}, scheduled_at: at))

jobs/continue.ex
- def perform(%Oban.Job{args: %{"thread_id" => tid}}) when is_integer(tid), do: Continuation.run(tid)
+ def perform(%Oban.Job{args: %{"thread_id" => tid} = args}) when is_integer(tid),
+   do: Continuation.run(tid, quiet: args["quiet"] == true)
```
Add a test: a `quiet: true` run that hits the gap enqueues a job carrying `quiet: true`, and that job nudges at the gap's end when the artifact is there but unmoved.

Follow-up (non-blocking): the Continue unique window is 30s on inserted_at, so repeated sweeps inside one gap can leave several scheduled jobs for one thread. The gap still caps nudges, but the jobs pile up. From reading Oban's unique semantics, not from a run.

Verified by reading the diff and call sites only; the test suite was not run.