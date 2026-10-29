# Review: stop-smoke-cancels-a-building-or-queued @ 60fced6

**Verdict: request_changes** — the mechanism is right and matches the brief; two small things, both in the change's own files, one round.

Read: the diff against origin/main (4 files, +60/−10), `Server.Smoke`, `Server.Jobs.Smoke`, `smoke_test.exs`, `scripts/release-smoke.sh` lines 41–54 (`trap cleanup EXIT` / `trap 'exit 143' TERM INT`). CHECKS: `mise run check` exit 0 on 60fced6 at verify; no bench_contrast row (no persona edit), so nothing to say there. No spec.md/plan.md: the workline opened at build from ticket #536, expected.

## What the diff does, as a witness

- `perform/1`: `job = stamp(job, %{"os_pid" => os_pid, "log" => log})` right after `Port.open`, before `pump/6`. ✓ brief item 1.
- `stop/1`: `case held(thread_id) || building(thread_id)` — a job with `"os_pid"` gets `kill -TERM`; `available`/`scheduled` gets `Oban.cancel_job(id)` (returns `:ok`, matches the spec); an executing job with no pid yet gets `building_error(..., "stop again in a moment")`. ✓ brief item 2.
- Tests: the combined "drive and stop say it is building" split in two; two new tests (TERM mid-build → `ended (exit 143)`, cancel queued → `cancelled`, then "no smoke is up"). The `trap 'exit 143' TERM` stub mirrors the real script's trap. ✓

## Findings

**1. Both moduledocs now contradict the code (blocking under AGENTS.md: docs in sync, same commit).**

`server/lib/server/smoke.ex:7-8` still reads:
> this module only finds the running one (an executing `Jobs.Smoke` whose meta carries the url) and stops it. A smoke still building has no url yet: `building/2` finds it, so drive and stop say so and a same-ref start returns it.

"stop say so" is the behaviour this ticket removes. And `server/lib/server/jobs/smoke.ex:5-6`:
> When the script says it is holding, the job records the url, the smoke's build dir … and the script's pid in its meta

The pid is now recorded at `Port.open`, before the hold. A weaker model reading either doc would conclude stop can't cancel a build.

Patch:
```
server/lib/server/smoke.ex
<<<<<<< SEARCH
  script keeps its own one-smoke-per-commit lock; this module only finds the running one
  (an executing `Jobs.Smoke` whose meta carries the url) and stops it. A smoke still building has
  no url yet: `building/2` finds it, so drive and stop say so and a same-ref start returns it.
=======
  script keeps its own one-smoke-per-commit lock; this module only finds the thread's job and
  stops it: `held/1` is the one up (its url in meta), `building/2` the one queued or still building
  (no url yet) — drive says so and a same-ref start returns it; stop TERMs its script once it has a
  pid, or cancels the job when it has no process yet.
>>>>>>> REPLACE
server/lib/server/jobs/smoke.ex
<<<<<<< SEARCH
  `stop_smoke` or the script's own hold TTL. When the script says it is holding, the job records
  the url, the smoke's build dir (`Server.Smoke.drive/2` runs the candidate's drive from it) and the script's pid in its meta (what `Server.Smoke` finds it by) and posts the url and the
  log's path on the thread; a smoke that fails posts its last lines instead. One attempt: a retry
=======
  `stop_smoke` or the script's own hold TTL. The job records the script's pid and log in its meta
  as soon as it starts (so `stop_smoke` can TERM a build); when the script says it is holding it
  adds the url and the smoke's build dir (`Server.Smoke.drive/2` runs the candidate's drive from it),
  what `Server.Smoke` finds it by, and posts the url and the
  log's path on the thread; a smoke that fails posts its last lines instead. One attempt: a retry
>>>>>>> REPLACE
```

**2. `%{meta: %{"os_pid" => pid}}` also matches a `null` pid (minor, same round).**

`perform/1` comments it itself: `os_pid` is nil "when the script already exited". `stamp` then writes `"os_pid": null`, which reads back as `nil` and matches the clause, so `stop/1` runs `kill -TERM ""` and answers `:ok`. Harmless (the job is ending anyway) but it is a kill with an empty argument. Guard it so nil falls through to the "stop again in a moment" answer:
```
server/lib/server/smoke.ex
<<<<<<< SEARCH
      %{meta: %{"os_pid" => pid}} ->
=======
      %{meta: %{"os_pid" => pid}} when is_integer(pid) ->
>>>>>>> REPLACE
```
Existing tests cover both sides of the guard (held: os_pid set; executing-no-pid: meta has no key).

## Not findings, noted

- `hold/4` still stamps `os_pid`/`log` a second time: redundant now, harmless, leave it.
- Race between the `building/1` read and `Oban.cancel_job` (a job picked up in between would have its executor killed, orphaning the port): the window is two queries wide and the script dies on SIGPIPE at its next write, which runs its EXIT cleanup. Not worth a lock.
