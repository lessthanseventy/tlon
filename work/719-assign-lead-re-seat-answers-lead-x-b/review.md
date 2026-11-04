# Review: 719-assign-lead-re-seat-answers-lead-x-b @ c4e3b13

**Verdict: approve.** Uqbar's three asks from the gate (message 28838) are each done as asked, each with a test that was red first, and nothing beyond them moved. My two earlier rounds' findings stay fixed (review at 6e08e39).

Read: `git show c4e3b13` (`staffing.ex`, `switchboard.ex`, both tests), `Switchboard.deliver_now/1`, `claim_reached/1`, `reaches_nobody?/1`, `claim/1`, `maybe_spawn_absent/1`, `Runner.safely/2`, the switchboard test's `setup`. CHECKS: verify's `mise run check` exit 0 on the branch; I ran `menard run test --in server test/server/staffing_test.exs test/server/switchboard_test.exs` myself: 118 tests, 0 failures. No `bench_contrast` row (the diff touches no persona file, so none was due).

## 1. Done: a notice never opens a pane

Witness, `switchboard.ex` `deliver_now/1`:

    if reaches_nobody?(message), do: claim([message.id]), else: maybe_spawn_absent(message)

That is `claim_reached/1`'s line verbatim, so the live path and the drain now settle the same set: notice, suggestion, margin, side project, a closed thread, a message addressed only to its author. The refusal notice `note_unseated/2` posts is kind `notice`, so `Channel.post`'s broadcast through `Runner` claims it and spawns nobody; the loop Uqbar named (refusal → notice → spawn → refusal) is closed at the source, not by the dedupe. Tests: a notice delivered to a cold thread's lead gets `refute_received {:spawned, _}`; `ChangingRefusalArbiter` (a fresh `{:tmux, n}` per call) yields one "could not be seated" notice after the handoff post plus every notice redelivered by hand. The test module's `setup` resets `:arbiter` on exit, so the test's own `put_env` without `on_exit` is covered.

Residual, said plainly: a *changing* refusal text still posts one new notice per drain retry of the handoff post itself (one a minute, the drain's cadence), since the dedupe matches the exact body. That is the bounded case Uqbar accepted; the unbounded one is gone.

## 2. Done: hand_off survives a raising delivery

Witness, `staffing.ex`:

    try do
      Server.Switchboard.deliver(message)
    rescue
      e -> Logger.error("hand_off delivery on thread #{thread.id} failed: #{Exception.message(e)}")
    end

`Runner.safely/2` is the same bare `rescue` with a `Logger.error`, so this is exact parity, not a looser copy; `require Logger` is already in the module. `RaisingArbiter.spawn/1` raises and the test still gets `{:ok, _}` with `thread_lead == "hronir"`, so the doc's "Every error changes nothing" and the reassignment agree again. An `exit` would still escape both, as it does in Runner; not asked for, not new.

## 3. Done: the doc says the seat may wait

The `@doc` now lists the three holds `deliver/1` applies (office or thread paused, a dialog waiting, a restart pending) and that the drain delivers the held post. It matches the `if` in `deliver/1` line for line.

## Noted, not a change

`deliver_now/1` still answers `{:pending, message}` for a notice it has just claimed, so the row says delivered while the call says pending. Both callers (`Runner`, `hand_off`) discard the value, so nothing reads the lie; a nit, left here rather than filed.

Verify's check tail again ends `tlon/check: not posted — gh: No commit found for SHA 14f1faf…`: the gate's rebased sha is not on GitHub before landing, expected and not this branch's.