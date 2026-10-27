# Plan: auto pencils down at a plan-meter threshold (#403)

Spec: `spec.md` beside this file. Three tasks, one commit each, in order. All paths under `server/`.
Run tests with `~/projects/menard/bin/menard run test --in server <file>`; edit Elixir with `menard edit`.
Commit trailer: `Co-Authored-By: <your model> <noreply@anthropic.com>`.

**One deviation from the spec:** the knob is *not* nullable. `OperatorConfig.value/2` turns a nil into the
default, so with default 90 a nullable knob could never be "off". It is an int 1–100; 100 is as near off as
a meter gets. (Spec line "nullable (nil = off)" and its "knob nil" test case are dropped; say so in the PR.)

## Task 1 — the knob
Files: `lib/server/operator_config.ex`, `test/server/operator_config_test.exs`.

Test first (add to the `knobs` test near line 33):
```elixir
assert %{value: 90, type: "int", min: 1, max: 100} = knobs["auto_pause_at"]
```
Red (no such knob). Then add to `@knobs` after `auto_land_risk`:
```elixir
%{
  key: "auto_pause_at",
  type: "int",
  min: 1,
  max: 100,
  default: 90,
  doc: "plan meter percent (5-hour or weekly) at which the office goes to pencils down by itself"
},
```
Done: `menard run test --in server test/server/operator_config_test.exs` green. Check whether the moduledoc
lists knobs by name; if so add this one.

## Task 2 — `Server.Pause.auto/1`
Files: `lib/server/pause.ex`, `test/server/pause_test.exs` (its setup already gives a temp settings file,
a `lobby` machine thread and DB; use `bodies(lobby)`).

Tests first (red: `Pause.auto/1` undefined):
```elixir
describe "auto/1" do
  @hot %{five_hour: %{percent: 91, resets_at: "2026-10-27T14:00:00Z"}}

  test "a window at the threshold while working pauses and says why on the lobby", %{lobby: lobby} do
    assert :ok = Pause.auto(@hot)
    assert Pause.state() == :pencils_down
    assert Enum.any?(bodies(lobby), &(&1 =~ "5h at 91%" and &1 =~ "14:00" and &1 =~ "back to work when you say"))
  end

  test "below the threshold nothing happens" do
    assert :ok = Pause.auto(%{five_hour: %{percent: 89, resets_at: nil}})
    assert Pause.state() == :working
  end

  test "after back_to_work the same {window, resets_at} does not fire again; a new resets_at does" do
    Pause.auto(@hot)
    {:ok, :working} = Pause.back_to_work()
    Pause.auto(@hot)
    assert Pause.state() == :working
    Pause.auto(%{five_hour: %{percent: 91, resets_at: "2026-10-27T19:00:00Z"}})
    assert Pause.state() == :pencils_down
  end

  test "a manual pause is left as it is, and says nothing", %{lobby: lobby} do
    {:ok, :lights_out} = Pause.lights_out()
    before = bodies(lobby)
    Pause.auto(@hot)
    assert Pause.state() == :lights_out
    assert bodies(lobby) == before
  end

  test "the weekly window counts too", %{lobby: lobby} do
    Pause.auto(%{seven_day: %{percent: 95, resets_at: nil}})
    assert Enum.any?(bodies(lobby), &(&1 =~ "weekly at 95%"))
  end
end
```
Implement in `Server.Pause` (after `back_to_work/0`):
```elixir
@doc """
A plan meter reading (`%{five_hour?: w, seven_day?: w}`, `w = %{percent, resets_at}`): at the
`auto_pause_at` knob, pencils down and the reason on the lobby. Only from :working; a window that
already paused the office (`{window, resets_at}`, kept in the settings file) never pauses it again, so
the operator's back_to_work sticks. Always `:ok`.
"""
def auto(windows) do
  limit = OperatorConfig.setting("auto_pause_at")
  latched = OperatorConfig.read()["auto_paused_for"]

  with :working <- state(),
       {name, %{percent: p, resets_at: r}} <-
         Enum.find(windows, fn {name, w} -> w.percent >= limit and latch(name, w) != latched end) do
    :ok = OperatorConfig.put("auto_paused_for", latch(name, %{resets_at: r}))
    {:ok, _} = pencils_down()
    auto_say(name, p, r)
  end

  :ok
end

defp latch(name, %{resets_at: r}), do: "#{name}|#{r}"

defp auto_say(name, percent, resets_at) do
  label = if name == :five_hour, do: "5h", else: "weekly"

  reset =
    with r when is_binary(r) <- resets_at,
         {:ok, at, _} <- DateTime.from_iso8601(r),
         do: ", resets #{Calendar.strftime(at, "%H:%M")} UTC",
         else: (_ -> "")

  body = "#{label} at #{round(percent)}%#{reset} — pencils down, back to work when you say"

  with %Server.Thread{id: id} <- Channel.machine_thread(),
       do: _ = Channel.post(%{thread_id: id, author: "tlon", body: body, kind: "notice"})
end
```
Done: `menard run test --in server test/server/pause_test.exs` green.

## Task 3 — wire it to the report path
Files: `lib/server/usage.ex`, `test/server/usage_test.exs`.

Test first (red: office stays :working). usage_test has no DB or temp settings file, so give it the
`pause_test` setup (`TestDB.clean!/0`, temp `:operator_config_path` restored in `on_exit`, a registered
workspace with a `scope: "machine"` thread) before adding:
```elixir
test "a report at the threshold pauses the office and says why on the root thread", %{lobby: lobby} do
  :ok = Usage.report(%{"five_hour" => %{"percent" => 92, "resets_at" => "2026-10-27T14:00:00Z"}})
  assert Server.Pause.state() == :pencils_down
  assert Enum.any?(Server.Channel.thread_messages(lobby), &(&1.body =~ "5h at 92%"))
end
```
(The existing tests, all under 90 %, keep passing: nothing fires.) Implement: in `report/1`'s `true ->`
branch, after the `Agent.update`, call `Server.Pause.auto(windows)` and return `:ok`:
```elixir
true ->
  Agent.update(__MODULE__, &Map.merge(&1 || %{}, Map.put(windows, :at, DateTime.utc_now())))
  Server.Pause.auto(windows)
```
Also update the `Server.Usage` moduledoc (one sentence: a window at `auto_pause_at` puts the office on
pencils down, `Server.Pause.auto/1`) and the "known limit" (meter is nil after a restart, so this never
escalates past pencils down). `lib/server/mcp/operator_api.ex:27` needs no change.
Done: `menard run test --in server test/server/usage_test.exs test/server/pause_test.exs` green, then
`menard run check --in server` green; advance (the full gate runs on verify).

## After
File the follow-up ticket: auto-resume at `resets_at` (needs a timer).
