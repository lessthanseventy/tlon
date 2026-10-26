# Review: fix-flake-contrasttest-every-call-draws

**Verdict: approve.**

One commit, df260fb, test-only plus pr.md. Read against the ask (ticket #653) and `Server.Bench.Contrast`.

1. **The flake is gone by construction.** The stub answers `{"", :timeout}` with no sleep, so the only way `left <= 0` before the first call is 60 s elapsing between `Contrast.run`'s deadline (contrast.ex:24) and `json/3`'s read (contrast.ex:140). `assert left in 1..60_000` still proves the call got the run's remaining wall and `why =~ "wall"` still proves the timeout row names it. Exactly what the ask prescribed.
2. **The spent-wall branch is now covered on purpose.** `wall_ms: 0` makes `left <= 0` true on any load, `refute_received :exec_called` proves exec is skipped, and the row text matches contrast.ex:144 (`"… not run: the 15-minute wall is spent"`). Deterministic, no timing.
3. **Nit, non-blocking:** the new test's title says "each side is a not-run error row", but with the wall spent at main's `--fingerprint` call, `bench/2`'s `with` short-circuits (contrast.ex:113-118) and the test asserts one row, main's. The behaviour is right; the title overstates. Not worth a round trip.

Verified: `menard run test --in server test/server/bench/contrast_test.exs` → 16 tests, 0 failures, here. CHECKS hold a green `mise run check` on the branch (verified in a train with #366). No bench_contrast row, so nothing to contrast.
