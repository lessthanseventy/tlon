# Review: start-smoke-idempotency-on-the-resolved @ 56024a7 (round 3)

**Verdict: approve.** The one blocking finding from rounds 1 and 2 is fixed in 56024a7, and the fix is the one the review gave. The witness (`git diff a880dd4..56024a7 -- server`):

```elixir
defp replace(old, thread_id, ref, sha, opts) do
  case stop_job(old) do
```

## 1. `replace/5` now cancels the job it found (fixed)

`stop/1`'s three job clauses are lifted into `stop_job/1`; `stop/1` keeps its nil clause and delegates, so its behaviour is unchanged (pid → TERM, available/scheduled → `Oban.cancel_job`, executing-without-pid → the "stop again in a moment" error). `replace/5` calls `stop_job(old)` on the job `building(thread_id, ref)` returned, not a fresh `building(thread_id)` across every ref. The two-ref scenario from round 2 now goes: A (`main`) stays `available`, B (`work/x` at s1) is cancelled, the new job's `meta.replaced` is B's id.

The new test is that scenario verbatim: queue `main`, queue `work/a-thing`, move the resolver, start `work/a-thing` again; asserts `replaced == old.id`, old `cancelled`, the `main` job still `available`. Round 2's "can't be cancelled yet" test stays green under `stop_job(old)` (executing, no pid → error clause → start's own wording).

## Checked and sound (whole branch, origin/main..56024a7)

- Resolve once at start, in `main_root`'s shared git dir, `git rev-parse -q --verify <ref>^{commit}`; nothing fetched in the request path.
- `sha` stored in args beside `ref`; `queue/3` returns the existing job only on `args.sha == sha`, replaces on a mismatch, refuses an unresolvable ref with `no commit <ref>` and nothing queued.
- The script still takes the ref; the MCP result carries `replaced` with the cancelled job's id.
- `building/2` @doc and the moduledoc say same commit / moved tip replaces.
- Test setup installs and deletes the `:smoke_resolve` knob; no test leaks it.
- CHECKS: the server's verify ran `mise run check` green on this branch at 18:12:50Z (the 18:03Z red was the office `navigation.test.ts:109` toy timeout, not a file this branch touches; emma recorded it on #452). No `bench_contrast` row among the checks shown, as expected for a non-steering change.

## Still open, not blocking

Follow-up 1 from round 1 (the script re-resolves the ref at run time, so `args.sha` can go stale between queue and execution) is #538–#540 scope by hronir's call; carried in follow_ups so it isn't lost.
