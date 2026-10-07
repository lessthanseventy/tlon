# Plan — workline dbconnection-client-exited (ticket #9)

## What changed since spec.md

The spec's leading hypothesis (`Server.Switchboard.opening_turn/2`'s background task racing
`test_db.ex`'s 5s force-kill) is **retracted**. A diagnostic added to the force-kill branch never
fired across ~20 reproductions of the disconnect, ruling it out directly.

The real root cause (found by the operator while landing a related fix, independently confirmed
by this agent hitting the same symptom from a different angle — a `storage_down`/`storage_up`
race giving `{:error, :already_up}` on its own run): `server/test/test_helper.exs` drops and
recreates the suite's Postgres database (`storage_down` + `storage_up`) at the start of **every**
`mix test` run. Before this fix, every checkout shared one `tlon_test` database, so a second suite
starting anywhere — a coworker's worktree, a gate, a `verify` stage — deleted the database out
from under a run already in progress, and every connection that run held died, logged as exactly
this "client exited" line. Matches the timing (since 2026-09-25, when worktrees began running
suites concurrently) and the rate (0–2 per run: however many *other* suites happened to start
during this one's window).

This has already landed on `main`: `03413a6 tests: each checkout its own test database — a run
drops and recreates it` — `config/test.exs` now derives `tlon_test_<worktree-name>` per checkout
(`tlon_test` only for the main checkout with no `.worktrees/` in its path), so two checkouts can no
longer collide. `work/dbconnection-client-exited` has been rebased onto `main`, picking this up.

There is therefore **no code fix left for this workline to write** — `spawn_ready_timeout_ms` is
dropped per the operator's instruction, and no other fix is justified without evidence the bug
still reproduces after the rebase. The remaining work is verification.

## Task 1 — verify: two worktrees running `mix test` at the same time, several rounds, zero disconnects

**No new file.** Run from two already-rebased worktrees (this one,
`.worktrees/dbconnection-client-exited`, and any other checkout at or past `03413a6` — e.g.
`.worktrees/home-dollies-looks`), concurrently, 5 rounds each side:

```sh
# worktree A
cd .worktrees/dbconnection-client-exited/server
for i in $(seq 1 5); do
  mix test > /tmp/verify_a_$i.log 2>&1
  echo "A run $i exit:$? disconnects:$(grep -c 'DBConnection.ConnectionError' /tmp/verify_a_$i.log)"
done

# worktree B, running at the same time
cd .worktrees/home-dollies-looks/server
for i in $(seq 1 5); do
  mix test > /tmp/verify_b_$i.log 2>&1
  echo "B run $i exit:$? disconnects:$(grep -c 'DBConnection.ConnectionError' /tmp/verify_b_$i.log)"
done
```

**Definition of done**: every `disconnects:` count above is `0`, across all 10 runs (5 per
worktree, both sides actually overlapping in wall-clock time — that's the condition that used to
trigger this). Grep the exact string `DBConnection.ConnectionError` (not `client exited` — that
substring never matches, because the real log line is `client #PID<...> exited`; this is the
counting bug this agent made earlier in the investigation and had to re-derive from scratch —
don't repeat it).

If any run shows a nonzero count: **stop, do not add a fix speculatively.** Capture the full log,
find which test/process it correlates to (`mix test --trace` on that worktree alone first, to get
clean per-test attribution — see spec.md's "Reproduction" section for the technique: the
disconnect line will print bracketed between two test-result lines in `--trace` output), and
report that evidence on ticket #9 / this thread before writing any further task.

## Task 2 — report on ticket #9

**No file.** Once Task 1 is green, record on ticket #9 (and this thread) that:
- the shared-test-DB race was the cause,
- it's fixed by `03413a6` on `main`,
- this workline rebased onto it and reverified with a concurrent two-worktree run showing zero
  `DBConnection.ConnectionError` lines,
- `spawn_ready_timeout_ms` was considered and dropped — the diagnostic showed it was never the
  trigger.

Use `mcp__tlon__update_ticket` (or `tlon-cli`) against ticket #9, not just a thread post — the
ticket is the durable record.

## Exit

Commit nothing beyond this `plan.md` for this stage. Verification (Task 1) runs in `build`/
`verify`; this plan's job is to hand the engineer in that stage the exact command and the exact
"stop and report" condition if it still reproduces, since the evidence found so far says it
shouldn't.
