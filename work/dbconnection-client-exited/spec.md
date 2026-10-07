# Spec — workline dbconnection-client-exited (ticket #9)

> **Superseded — see `plan.md`.** The "leading hypothesis" and "fix" sections below (the
> `opening_turn`/`await_background` 5s-kill theory, and the `spawn_ready_timeout_ms` change) were
> disproven: a diagnostic on the force-kill branch never fired across ~20 reproductions. The real
> cause was the shared test database (`test_helper.exs` dropping/recreating `tlon_test` under a
> concurrent run) — fixed on `main` at `03413a6`. Left in place below as the investigation record;
> do not act on the "Fix" section.

## Problem

`server:check` intermittently (0–2 lines per gate run, since 2026-09-25 09:13) logs:

```
[info] Postgrex.Protocol disconnected: ** (DBConnection.ConnectionError) client #PID<...> exited
```

This fires when the OS process that checked out a Postgrex connection terminates **without**
checking it back in — i.e. it was killed, not merely raised inside a `Repo.transaction`/
`Repo.checkout` (Ecto's own `try/after` already releases the connection on a normal exception).
The fix must find the process that gets terminated while still holding a connection and make it
either finish before anything would kill it, or hand the connection off cleanly.

## Reproduction (confirmed)

Reproduced twice, independently:

- `menard run check --in server` (async suite, `max_cases: 40`), log line 487 of
  `/tmp/menard-run/.../20261007T045733229012-check.log`:
  `Postgrex.Protocol (#PID<0.19229.0>) disconnected: ... client #PID<0.21885.0> exited`
- `mix test --trace` (fully serial), log `trace1.log`, line 3389 — the disconnect line printed
  **in the middle of** `Server.SwitchboardTest`'s own result output, specifically bracketing the
  test:

  > `test "the drain gives a closed pane's messages back, so the next drain spawns someone"`
  > (`test/server/switchboard_test.exs:422`)

  That test's own line took 29.8ms vs. 11–17ms for its neighbors — consistent with something still
  running past the test body.

Both reproductions point at the same place: that test calls `Switchboard.drain()` twice, and the
second call (`lib/server/switchboard.ex`, `opening_turn/2`) spawns a background Task under
`Server.TaskSupervisor` that polls pane readiness and then does a DB write (`claim/1`,
`Repo.update_all`).

## Leading hypothesis

`test/support/test_db.ex`'s `await_background/0` is the mechanism every test already relies on to
not leak background work across tests: on exit, it waits (via `Process.monitor`) for every child
of `Server.TaskSupervisor`, and — if one hasn't finished in **5 seconds** — hard-kills it with
`Process.exit(pid, :kill)`. A `:kill` is untrappable: if that process is mid-`Repo` call when it
lands, the checked-out connection is abandoned and Postgrex logs exactly this "client exited" line.

`Server.Switchboard.opening_turn/2`'s spawned task has no bound tying it to that 5s budget — it
polls `Arbiter.ready?/1` against `Application.get_env(:server, :spawn_ready_timeout_ms, 20_000)`
(a 20s default) before ever reaching the `claim/1` write. In `SwitchboardTest` the configured
`Server.Arbiter.Test.ready?/1` always returns `true` immediately, so in the common case the task
finishes in milliseconds — which is why this is rare (0–2 lines per run), not constant. The theory
is a timing fluke (GC pause, scheduler contention, test pool pressure) occasionally pushes that
task past the 5s mark before it reaches/finishes `claim/1`, and `await_background`'s fallback kill
catches it mid-write.

**Not yet proven**: a temporary diagnostic (`Logger.warning` in the 5s-timeout branch of
`await_background/0`, logging the killed pid's stacktrace) has been added and run ~15 times without
the kill branch firing — consistent with the error's low, intermittent rate, but it means the
build stage must keep this diagnostic (or something like it) running until it catches the kill
firing in the same run as a "client exited" line, to confirm this is the actual trigger before
trusting the fix below. The diagnostic lives at `test/support/test_db.ex` (see conversation/commit
history on this branch) — revert it once confirmed either way.

## Fix

Once confirmed: give `Server.Switchboard.opening_turn/2`'s background task no way to still be
alive when `await_background/0`'s patience runs out, by bounding it to a budget safely under 5s
*in tests* — add `config :server, spawn_ready_timeout_ms: 1_000` (or similar) to
`config/test.exs`. This is a one-line, test-env-only change: it doesn't touch the production
default (20s is right for a real backend genuinely waiting on a pane to come up), and it fixes
every test that goes through `opening_turn`, not just the one that happened to trip it — the
general shape the ticket asks for ("make it await or allow the connection").

If the diagnostic instead shows a *different* task (not `opening_turn`) is the one being killed,
the same fix shape applies to whichever call site it is: either bound its background work under
the test's wait budget, or have the test `assert_receive`/otherwise wait for it directly instead
of relying on `await_background`'s fallback kill.

## Acceptance

- `menard run check --in server` run repeatedly (at minimum the number of times it takes to
  reproduce once pre-fix, as a baseline) never logs `client exited` after the fix.
- The existing `Server.SwitchboardTest` suite (and the rest of `mix test`) stays green —
  `menard run check --in server` reports `ok` with no new failures.
- The temporary diagnostic added during this investigation is removed (or, if kept, demoted to
  something permanent and intentional, not a leftover debugging aid) before this workline reaches
  `review`.

## Out of scope

- The 5 unrelated `Server.CommitsTest` failures seen in one of this investigation's gate runs are
  an artifact of this agent's own session running inside tlon thread #131 (`TLON_THREAD=131` in
  env trips the "refuse to commit on main" guard those tests exercise) — not this ticket, and not
  reproducible in a clean environment.
