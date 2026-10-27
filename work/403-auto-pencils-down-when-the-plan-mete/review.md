# Review: auto pencils down at a plan-meter threshold (#403)

**Verdict: request_changes.** Branch `work/403-auto-pencils-down-when-the-plan-mete` at 7ee5f33 (code at 1a9328c; 7ee5f33 is pr.md only). Diff read in full: `operator_config.ex`, `pause.ex`, `usage.ex`, the three tests, spec, plan, pr.md. CHECKS: `menard run check --in server` ok 2237/0 and the server's `mise run check` green on the branch. No bench_contrast row (no persona file touched), so nothing to weigh there.

One blocking finding, by reading, not by running (I cannot write the red test; it is below for the builder to add):

## 1. The latch is one slot, so back_to_work does not stick when both windows are hot — BLOCKING

The witness, `pause.ex`:

```elixir
latched = OperatorConfig.read()["auto_paused_for"]
...
Enum.find(windows, fn {name, w} -> w.percent >= limit and latch(name, w) != latched end) do
  :ok = OperatorConfig.put("auto_paused_for", latch(name, %{resets_at: r}))
```

`auto_paused_for` holds exactly one `"window|resets_at"` string, and every window is compared against that one string. Trace with both windows over the knob (the ordinary end of a week: weekly at 92%, each 5h window crossing 90%), `Enum.find` iterating a small map in key order, `:five_hour` first:

1. Report: 5h|R1 fires, latch = `"five_hour|R1"`, pencils down. Operator: back to work.
2. Report: 5h|R1 == latch, skipped; weekly|R2 != latch, fires, latch = `"seven_day|R2"`. Operator: back to work.
3. Report: 5h|R1 != `"seven_day|R2"`, fires again. The 5h override from step 1 is gone.

So the office re-pauses on every whole-point move, alternating windows, for as long as both stay over the knob. That is the spec's requirement b ("the operator's back_to_work is the override, and it has to stick") broken in the common case. The existing test covers one window only, which is why it is green.

Fix: one slot per window. A window's `resets_at` only moves forward, so a map window → last resets_at that fired is enough.

```diff
--- a/server/lib/server/pause.ex
+++ b/server/lib/server/pause.ex
@@
   `auto_pause_at` knob, pencils down and the reason on the lobby. Only from :working; a window that
-  already paused the office (`{window, resets_at}`, kept in the settings file) never pauses it again, so
-  the operator's back_to_work sticks. Always `:ok`.
+  already paused the office (its `resets_at`, kept per window in the settings file) never pauses it
+  again, so the operator's back_to_work sticks. Always `:ok`.
   """
   def auto(windows) do
     limit = OperatorConfig.setting("auto_pause_at")
-    latched = OperatorConfig.read()["auto_paused_for"]
+    latched = latched()
 
     with :working <- state(),
          {name, %{percent: p, resets_at: r}} <-
-           Enum.find(windows, fn {name, w} -> w.percent >= limit and latch(name, w) != latched end) do
-      :ok = OperatorConfig.put("auto_paused_for", latch(name, %{resets_at: r}))
+           Enum.find(windows, fn {name, w} ->
+             w.percent >= limit and Map.get(latched, to_string(name), :none) != w.resets_at
+           end) do
+      :ok = OperatorConfig.put("auto_paused_for", Map.put(latched, to_string(name), r))
       {:ok, _} = pencils_down()
       auto_say(name, p, r)
     end
 
     :ok
   end
 
-  defp latch(name, %{resets_at: r}), do: "#{name}|#{r}"
+  # One slot per window, so one window firing never forgets the other's override.
+  defp latched do
+    case OperatorConfig.read()["auto_paused_for"] do
+      %{} = m -> m
+      _ -> %{}
+    end
+  end
```

`:none` as the miss default keeps a first `resets_at: nil` window firing (nil == nil would otherwise read as already latched). The red test, in `pause_test.exs` under `describe "auto/1"`:

```elixir
    test "each window latches on its own: the weekly firing doesn't forget the 5h override" do
      both = %{
        five_hour: %{percent: 91, resets_at: "2026-10-27T14:00:00Z"},
        seven_day: %{percent: 92, resets_at: "2026-10-30T00:00:00Z"}
      }

      Pause.auto(both)
      {:ok, :working} = Pause.back_to_work()
      Pause.auto(both)
      assert Pause.state() == :pencils_down
      {:ok, :working} = Pause.back_to_work()
      Pause.auto(both)
      assert Pause.state() == :working
    end
```

Red on 1a9328c at the last assert (step 3 above); green with the map latch. Nothing shipped yet reads `auto_paused_for`, so the shape change needs no migration.

## 2. Spec deviation on nullability: correct as declared — not blocking

pr.md says the knob is int 1–100, not nullable, because `OperatorConfig.value/2` turns nil into the default. Verified in `operator_config.ex`: `value/2` matches `{:ok, v} when not is_nil(v)` and otherwise returns `knob.default`, and `put_settings/2` deletes the key on nil. So nullable-with-default is unreachable off on main as it stands; `auto_land_risk` only works because its default is nil, and `max_session_hours` has the same latent fault. The builder's call is the right one for this change; the knob fix is a follow-up (filed), after which `auto_pause_at` can go nullable as the spec wanted.

## 3. Everything else checked

- Spec a, c, d met: knob per bucket (whichever crosses first), fires only from `:working` (tested with lights out; manual pencils down takes the same `state()` branch), no auto-resume (#672 exists).
- Spec e: the Usage moduledoc states the in-memory limit and that this never passes pencils down. OperatorConfig's moduledoc names the knob. The office settings panel reads `knobs/1`, so the knob appears there without a UI change.
- `Usage.report/1` still returns `:ok` (`auto/1` always does), so the HTTP door's contract is unchanged; the reading is stored before the compare, so a pause never loses a report.
- `round(percent)` is fine on an integer or float. `resets_at` is printed in UTC and says so.
- Tests: `usage_test` now cleans the DB and points the config path at a temp file, like `pause_test`; both `async: false`.

Nits, no action required: the lobby gets two lines (the generic pencils-down line from `go/1`, then the reason), where the spec pictured one; folding the reason into `lobby/1` would spare the operator a line. `server/AGENTS.md`'s pause bullet doesn't mention the meter as a trigger; a half-line there when the module is next touched.
