# Review: mod.ts: count a background subagent from agent.spawn, not turn.start (#546) — round 2

**Verdict: approve.** Branch work/mod-ts-count-a-background-subagent-from @ 1ebc3c1, diffed against origin/main (merge-base 14d491c). Since my approve at 98a5c7e the diff outside `work/` is one line in `server/test/server/release_smoke_script_test.exs`; mod.ts, mod.test.ts and README are byte-identical to what I reviewed, so findings 1–6 of the first round stand unchanged.

## Verified

- The CHECKS row for this round's verify: `mise run check` exit 0 at 00:39:57Z (server 2428/2428 by the merge-queue's count less the one fixed; office 958 pass). No `bench_contrast` row.
- Commit trailer `Co-Authored-By: claude-sonnet-5-5` matches `Tlon-Model: anthropic/claude-sonnet-5-5`.
- Not run by me: the Elixir file. The sandbox has no Postgres or checks queue; the server's verify row is the evidence.

## Findings on the delta

1. **The merge-queue red was not this change's.** It failed `the fetch of origin a holder that is gone … is reclaimed, not refused`, a test on main that this TS-only branch never touched. The queue told the builder to fix it on the branch, so its presence here is sanctioned, not scope creep.
2. **The cause is real and the fix is the right shape.** The witness: `-      stale_lock(tmp, root, "pid 9999999 on http://127.0.0.1:4777\n")` → `+ … http://127.0.0.1:#{free_port()}\n`. The smoke script treats a url that answers as a live holder; a service on :4777 answered during the full run, so the "gone" holder read alive. `free_port/0` (line 41) binds :0 on loopback, reads the port, closes it — a port nothing answers on now. Every other stale-record test in the file (lines 248, 495) already used it; this one was the lone fixed port on the reclaim path.
3. **The one `4777` left (line 217) is correct to leave.** That test holds a fresh lock (not aged to 2020), so the script refuses on "a record too young to be a finished build" before it probes the url; the port is only echoed in the assertion. Not load-dependent.
4. **RED reproduced, by the builder's account:** emma served 200 on :4777, the test failed with "already being smoked", and with the fix passed 27/27 under the same listener (msg 17675). I could not reproduce from a sandboxed seat; the green verify row is consistent with it.

## Still open, unchanged

Follow-up 1 from round one (the foreground Agent live proof) is restated below. #545 and hronir's typecheck ticket stay their own.
