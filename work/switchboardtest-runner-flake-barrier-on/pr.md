Fix the SwitchboardTest Runner flake (ticket #501, closes issue #51).

The two Runner live-path tests waited for `{:woke, "wSandra", _}` with `assert_receive … 1000`. Under CPU saturation that wait could expire before the wake arrived, and #306's verify went red on it.

Now each test does `:sys.get_state(Runner, :infinity)` and then `assert_received`. Runner drains in `handle_continue` and sends `:woke` from inside its own process, so the synchronous call returns only after the wake has been sent. The timed wait is gone; nothing else changed.

Checked:
- GREEN under load (14 cores plus 28 busy loops): `switchboard_test.exs:857` repeated 300 times and `:866` repeated 300 times, 0 failures (log `.logs/20261020T172117-…`, 602 `Result: 1 passed`).
- Whole file once: `mix test test/server/switchboard_test.exs`, 56 passed.
- RED not reproduced: the unchanged asserts passed 200 + 300 repeats under the same load on this box. The flake did not show here, so the before-state is unverified.
- Run with `mix test --no-deps-check`: this checkout's `deps/` is stale against its own `mix.lock` (menard 0.6.1 vs 0.6.3, phoenix_template 1.0.4 vs 1.1.0) and Hex is unreachable from the sandbox. The gate on the server runs with real deps.
