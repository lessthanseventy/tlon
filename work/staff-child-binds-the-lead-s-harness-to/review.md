# Verdict: APPROVE

The fix is correct and the gate is green. staff_child now seats the lead on the CHILD via `Spawn.join(child, lead, assign: false)` + `Arbiter.spawn(exports)`, so the seat no longer depends on the brief's wording — a brief that @mentions another coworker no longer leaves the lead running on the lobby (#1), unable to act on the thread they lead. This is the ticket #152 report, exactly.

## Verified

**1. No double pane when the brief addresses the lead (the common case the test does not cover).**
`seat` runs after `Channel.post`, so the runner's `deliver` races it. When the brief falls back to `lead_name` (no other mention), both `seat` and `maybe_spawn_absent` would spawn the lead — but `Arbiter.Tmux.spawn` is idempotent per thread-leaf: `running/4` (`arbiter/tmux.ex:91`) finds the `@funes_thread`-tagged leaf and returns `{:error, :already_running}`, refusing the second. Whichever loses the race, exactly one pane comes up. The test arbiter has no such guard, but the test's brief mentions `@outsider`, so delivery spawns outsider — the double path is never taken there. Sound.

**2. `else: (_ -> :ok)` is the right shape.** It swallows `:no_arbiter` (headless service — the message stays a pending durable row, drain re-delivers), `:already_running` (already seated), and `:at_cap` (the comment's named best-effort case — the next message addressed to the lead seats them). `Spawn.join` itself cannot realistically fail here: the thread was just created in the same `execute` and the lead was resolved by `staff`, and `assign: false` skips `Staff.assign` so the lead slot is untouched. `seat` always returns `:ok`, so it cannot break the `with` chain.

**3. The seat composes rather than forks.** It uses the same `Spawn` + `Arbiter` seam the switchboard's `maybe_spawn_absent` uses, with `assign: false` matching the rider semantics (a crew role, a non-staffing join). The moduledoc's old false claim that `Server.Staffing` stands a leaf up (it is takedown-only) is replaced by what holds now.

**Gate.** Verify's `mise run check` is green on the branch (14:54:30, 9 evals passed, verify evidence recorded). The 11 failures hladik flagged are the pre-existing sandbox artifact (issue #18, `/proc/1/environ` leaking under bwrap) — verify runs in its own scrubbed env, not a pane sandbox, and passed. Not the branch.

## Follow-ups (non-blocking)

- `seated?/3`'s `tries` param is dead — it recurses with no `when tries > 0` guard, so the counter bounds nothing; the `after 1_000` is the only bound. The builder's held-aside polish adds a terminating clause.
- The test sets `:tmux_cmd` env that this path never reaches (the test arbiter is used). Dead setup line.

Neither is worth a re-spin.