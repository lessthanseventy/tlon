## VERDICT: approve

The Runner flake fix replaces a timed `assert_receive {:woke, "wSandra", _}, 1000` with a barrier — `:sys.get_state(Runner, :infinity)` then `assert_received` — in both live-path tests (switchboard_test.exs:857 and :866). One one-line comment per test states the load-bearing why. Nothing else changed.

### Barrier verified end-to-end (not just on the repeated-run evidence)

1. **Broadcast is synchronous.** `Server.Bus.broadcast` → `Phoenix.PubSub.broadcast` → `Registry.dispatch` → `send(subscriber_pid, msg)` (deps/phoenix_pubsub `pubsub.ex:365–388`). `send` puts the message in the recipient's mailbox before returning, so `{:message_posted}` is in Runner's mailbox before `Channel.post` returns.
2. **get_state is ordered after it.** `:sys.get_state(Runner, :infinity)` sends its system message after `Channel.post` returned, so Runner processes `{:message_posted}` first — `handle_info` → `Switchboard.deliver` → `waken` → `poke` → `Arbiter.Test` does `send(test_pid, {:woke, …})` (arbiter.ex:72, a direct `send`, no Task) — and only then replies to get_state. So `:woke` is in the test mailbox when get_state returns; `assert_received` (no timeout) then matches it.
3. **Drain test (:866) holds on the start path.** OTP runs `handle_continue(:drain)` before any mailbox message, so the drain's `:woke` is sent before the system message is processed.
4. **setup** sets `test_pid` = `self()` and arbiter = `Server.Arbiter.Test`, so `:woke` lands in the test process's mailbox. Confirmed at switchboard_test.exs:31–32.

### Why this is correct and minimal

- The comment is accurate: the `:woke` is sent from inside the Runner process (a direct `send` in `Arbiter.Test`, called synchronously through `deliver`/`waken`/`poke` from `handle_info`/`handle_continue`).
- `assert_received` with no timeout is the right pair for a barrier — a timeout would only mask a broken barrier. The known limitation (if wakes ever move to a Task, the barrier breaks) is real but excluded by the current synchronous delivery model and the in-process test arbiter.
- Surgical: only the two flaky tests, one comment each. No drive-by.

### Evidence

- Verify gate: `mise run check` exit 0 on the branch (workline artifact checks passed); whole file 56 passed.
- GREEN under load: :857 ×300 and :866 ×300 under 42 busy loops on 14 cores, 0 failures (record_check 8497).
- RED not reproduced: the unchanged asserts passed 200 + 300 repeats under the same load on this box. This is a property of the flake (not reproducible here), not a defect in the fix — the fix removes the timeout that was the flake's cause.

No blocking findings. No follow-ups.