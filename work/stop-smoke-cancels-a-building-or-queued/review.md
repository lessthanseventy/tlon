# Review: stop-smoke-cancels-a-building-or-queued @ 60648c1 (round 2)

**Verdict: approve** — both round-1 findings are fixed, in the change's own lines, as patched; nothing new.

Read: my round-1 review.md (b0cd15a), the delta `b0cd15a..60648c1` outside `work/` (3 files, +17/−6), `stop/1` in full. CHECKS: `mise run check` exit 0 on 60648c1 at verify (server + office green; `tlon/check` not posted because the server's tree was dirty, which is the status rule, not a failure); `menard run test smoke_test.exs` 21/0, builder reports red-first on the null-pid test. No bench_contrast row (no persona edit), so nothing to say there.

## Findings from round 1, checked against the delta

**1. Moduledocs contradicted the code — fixed.** `server/lib/server/smoke.ex:6-9` now reads "stop TERMs its script once it has a pid, or cancels the job when it has no process yet"; `server/lib/server/jobs/smoke.ex:5-6` says the pid and log are recorded "as soon as it starts (so `stop_smoke` can TERM a build)". Both are my patch, character for character, and both describe what `perform/1` and `stop/1` now do.

**2. `"os_pid" => nil` matched the TERM clause — fixed.** `stop/1` reads `%{meta: %{"os_pid" => pid}} when is_integer(pid) ->`; a nil pid falls past the available/scheduled clause (the job is executing) to the last one, "its script has not started yet; stop again in a moment". The new test sets `meta: %{"os_pid" => nil}` on the executing fixture and asserts `{:error, "building since " <> _}`. That is the exact shape I asked for, and the builder says it went red first (`:ok`), which is what the unguarded clause would return.

## Nothing new

- The guard does not touch the held path: `hold/4` stamps an integer `os_pid`, so a smoke that is up still TERMs. The existing "stop ends the hold" test still covers it.
- The two non-findings from round 1 stand: the redundant second stamp in `hold/4`, and the two-query cancel race whose loser dies on SIGPIPE into its EXIT cleanup.

## Still open, not blocking

The live check (start_smoke, stop_smoke mid-build, job ends within seconds with "ended (exit 143)") remains unrun; it needs a cut. Carried as the one follow-up.