# Review: auto pencils down at a plan-meter threshold (#403)

**Verdict: approve.** Branch `work/403-auto-pencils-down-when-the-plan-mete` at d7bda3f (code at 4ed471d; d7bda3f strips three debug `IO.inspect` lines from the test). Second round: the prior review at 79c73aa requested one change, and the diff since (`git diff 79c73aa..d7bda3f -- server/`) is exactly that change plus its test. CHECKS: the server's `mise run check` green on the branch at 07:52:56Z (exit 0); my own `menard run test --in server test/server/pause_test.exs test/server/usage_test.exs` 18/0 at d7bda3f (recorded). No bench_contrast row in the CHECKS shown; no persona file touched, so none expected.

## 1. The single-slot latch — FIXED

The witness, `pause.ex` at d7bda3f:

```elixir
latched = latched()
...
Enum.find(windows, fn {name, w} ->
  w.percent >= limit and Map.get(latched, to_string(name), :none) != w.resets_at
end) do
  :ok = OperatorConfig.put("auto_paused_for", Map.put(latched, to_string(name), r))
```

`auto_paused_for` is now a map window → last `resets_at` that fired, and each window is compared against its own slot. The ping-pong trace from round one (5h fires, back to work, weekly fires and overwrites, back to work, 5h fires again) no longer holds: step 3 finds `"five_hour"` still latched at R1 and skips it. The test I asked for is in `pause_test.exs` under `auto/1` and asserts `:working` after the second back_to_work with both windows hot. The builder reports it red before and green after; I confirmed green at d7bda3f, not red at 1a9328c (I do not rebuild old shas for a reviewed patch I wrote).

Round-trip checked: `OperatorConfig.put/3` writes any JSON value with no knob check and `read/1` decodes with string keys, so the map comes back as written; `to_string(name)` keys match. A window with `resets_at: nil` latches as JSON null and reads back nil, which equals nil, so it does not fire twice; a window never seen misses to `:none` and fires. Both are what the doc promises. `latched/0` falls to `%{}` on any non-map, so a settings file from before this change (a string in that key) cannot crash the report path.

## 2. Spec deviation on nullability — still open, not blocking

Unchanged from round one. `auto_pause_at` is int 1–100 with 100 as off, because `OperatorConfig.value/2` turns nil into the default and `put_settings/2` deletes the key on nil. Correct as declared in pr.md; the knob-level fix is a follow-up (listed below, carried over).

## 3. Everything else — unchanged, holds

Spec a, c, d met (per-bucket threshold, `:working` only, no auto-resume; #672 filed). Spec e stated in the Usage moduledoc. `Usage.report/1` still `:ok`, reading stored before the compare. Credo clean after d7bda3f.

Nits, no action required: the lobby still gets two lines on an auto-pause (the generic one from `go/1`, then the reason). `server/AGENTS.md`'s pause bullet doesn't name the meter as a trigger.
