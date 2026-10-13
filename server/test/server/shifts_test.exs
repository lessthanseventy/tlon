defmodule Server.ShiftsTest do
  # Day and night shifts on one bench: a seat is on the day shift, the night shift, or both (`all`,
  # every seat until it is put on one). Only the crew on shift is the bench staffing sees, so a
  # workspace with no shifts set works as it always has. A shift change restaffs a workline led by
  # someone going off the workline's own way; a plain thread waits for its lead's shift.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import ExUnit.CaptureLog

  alias Server.Channel
  alias Server.Shifts
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    {:ok, ws} = Workspaces.register(%{name: "Shifts"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius", archetype: "surveyor"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder", crew: "day"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "emma", archetype: "builder", crew: "day"})
    {:ok, dahlmann} = Workspaces.seat(ws.id, %{name: "dahlmann", archetype: "builder", crew: "night"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "quain", archetype: "librarian"})
    %{ws: ws, dahlmann: dahlmann}
  end

  @limit "  ⎿  Claude usage limit reached. Your limit will reset at 5pm (America/Denver).\nsome later output"

  defp names(ws), do: ws.id |> Workspaces.bench() |> Enum.map(& &1.name)
  defp lobby(ws), do: Channel.open_thread(%{title: "lobby", workspace_id: ws.id, scope: "machine"})
  defp labels(ask), do: Enum.map(ask.payload["options"], & &1["label"])

  test "a workspace with no crews set: every seat is on, and there is no crew to switch to" do
    {:ok, plain} = Workspaces.register(%{name: "Plain"})
    {:ok, _} = Workspaces.seat(plain.id, %{name: "solo", archetype: "builder"})
    assert names(plain) == ["solo"]
    assert Shifts.crews(plain.id) == []
    assert {:error, :unknown_shift} = Shifts.switch(plain.id, "night")
    assert names(plain) == ["solo"]
  end

  test "on shift is the crew on duty plus the seats on both; the tech lead is the on-shift crew's", %{ws: ws} do
    assert Shifts.current(ws.id) == "day"
    assert names(ws) == ["tertius", "hronir", "emma", "quain"]
    assert Workspaces.lead(ws.id).name == "hronir"

    {:ok, _} = Shifts.switch(ws.id, "night")
    assert Shifts.current(ws.id) == "night"
    assert names(ws) == ["tertius", "dahlmann", "quain"]
    assert Workspaces.lead(ws.id).name == "dahlmann"

    assert ws.id |> Workspaces.bench_all() |> Enum.map(&{&1.name, &1.crew}) ==
             [{"tertius", "all"}, {"hronir", "day"}, {"emma", "day"}, {"dahlmann", "night"}, {"quain", "all"}]
  end

  test "a shift change restaffs the going crew's worklines; their plain threads wait", %{ws: ws} do
    {:ok, built} = Server.Workline.open(%{title: "the drift note", slug: "drift", stage: "build", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(built.id, "hronir")
    {:ok, plain} = Channel.open_thread(%{title: "a question", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(plain.id, "emma")
    {:ok, sweep} = Channel.open_thread(%{title: "sweep", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(sweep.id, "quain")

    assert {:ok, %{restaffed: [built_id], waiting: [plain_id]}} = Shifts.switch(ws.id, "night")
    assert {built_id, plain_id} == {built.id, plain.id}

    assert Channel.thread_lead(built.id) == "dahlmann"
    assert Channel.thread_lead(plain.id) == "emma"
    assert Channel.thread_lead(sweep.id) == "quain"
    assert built |> Channel.thread_messages() |> Enum.any?(&(&1.body =~ "night crew is on"))
  end

  test "off shift is still on the bench for everything but picking: its model, the manager rule, a hire",
       %{ws: ws, dahlmann: dahlmann} do
    {:ok, _} = Shifts.switch(ws.id, "night")
    hronir = Server.Staff.agent_by_name("hronir")
    assert {:ok, _} = Workspaces.retarget(ws.id, hronir.id, %{model: "anthropic/claude-haiku-5-5"})

    {:ok, day_manager} = Workspaces.seat(ws.id, %{name: "tertius-day", archetype: "surveyor", crew: "day"})
    {:ok, wl} = Server.Workline.open(%{title: "w", slug: "managed", stage: "build", workspace_id: ws.id})
    assert {:error, _} = Channel.assign_lead(wl.id, day_manager.name)

    assert Shifts.hire_crew(ws.id) == "night"
    {:ok, plain} = Workspaces.register(%{name: "Unshifted"})
    assert Shifts.hire_crew(plain.id) == "all"
    assert dahlmann.crew == "night"
  end

  test "a workline whose kind has nobody on the incoming shift waits, and isn't claimed as restaffed", %{ws: ws} do
    {:ok, _} = Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer", crew: "day"})
    {:ok, rv} = Server.Workline.open(%{title: "review it", slug: "reviewing", stage: "review", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(rv.id, "lonnrot")

    assert {:ok, %{restaffed: [], waiting: [waiting]}} = Shifts.switch(ws.id, "night")
    assert waiting == rv.id
    assert {:error, :not_found} = Shifts.switch(999_999, "night")
  end

  test "Claude's usage-limit line, as Claude Code prints it, reads as out of quota; talk about limits doesn't" do
    assert Shifts.out_of_quota?("  ⎿  Claude usage limit reached. Your limit will reset at 5pm (America/Denver).\n")
    assert Shifts.out_of_quota?("❯ \n  5-hour limit reached ∙ resets 5pm\n")
    assert Shifts.out_of_quota?("You've hit your limit · resets 9am (America/Denver)")
    refute Shifts.out_of_quota?("  the rate limiter caps requests; when the limit is reached it waits")
    refute Shifts.out_of_quota?("")
  end

  test "out of quota: the lobby is offered the other crews — nothing switches by itself, and once per line", %{ws: ws} do
    {:ok, lobby} = lobby(ws)

    assert {:offered, ["night"]} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    assert Shifts.current(ws.id) == "day"
    assert [ask] = Server.Attention.open_asks()
    assert ask.thread_id == lobby.id
    assert ask.payload["summary"] =~ "5:00pm"
    refute ask.payload["summary"] =~ "later output"
    assert labels(ask) == ["night crew on", "stay on day"]

    assert :ok = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    assert [_one] = Server.Attention.open_asks()

    {:ok, plain} = Workspaces.register(%{name: "One crew"})
    {:ok, _} = Workspaces.seat(plain.id, %{name: "solo", archetype: "builder"})
    assert :ok = Shifts.quota_check(plain.id, "solo", "1/w1", @limit)
  end

  test "out of quota with no other crew: a quota Need until the pane clears — wait for the reset, or pencils down" do
    {:ok, plain} = Workspaces.register(%{name: "One crew out"})
    {:ok, _} = Workspaces.seat(plain.id, %{name: "solo", archetype: "builder"})
    {:ok, _} = lobby(plain)
    quota = fn -> Enum.filter(Server.Office.Needs.list(), &(&1.kind == "quota" and &1.workspace_id == plain.id)) end

    assert :ok = Shifts.quota_check(plain.id, "solo", "1/w1", @limit)
    assert [need] = quota.()
    assert need.level == "blocking" and need.text =~ "5:00pm"
    assert [%{actions: actions}] = Server.Alerts.build([need], [], DateTime.utc_now())

    assert %{label: "Pencils down", body: %{mode: "pencils_down"}} =
             Enum.find(actions, &(&1[:path] == "/api/office/pause"))

    assert %{label: "Wait for the reset"} = List.last(actions)

    assert :ok = Shifts.quota_check(plain.id, "solo", "1/w1", "back at work")
    assert quota.() == []
  end

  test "taking the offer puts that crew on, and the offer to come back waits for the reset", %{ws: ws} do
    {:ok, _} = lobby(ws)
    {:offered, _} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    [ask] = Server.Attention.open_asks()

    assert {:ok, _} = Server.Attention.answer_prompt(ask.id, "andrew", "1")
    assert Shifts.current(ws.id) == "night"
    assert Server.Attention.open_asks() == []
    assert_enqueued(worker: Server.Jobs.ShiftBack, args: %{workspace_id: ws.id, back: "day"})

    # the reset comes (Server.Jobs.ShiftBack)
    :ok = Shifts.offer_back(ws.id, "day", "5pm")
    assert [back] = Server.Attention.open_asks()
    assert labels(back) == ["day crew on", "stay on night"]
    assert {:ok, _} = Server.Attention.answer_prompt(back.id, "andrew", "1")
    assert Shifts.current(ws.id) == "day"

    # already back: nothing to offer
    :ok = Shifts.offer_back(ws.id, "day", "5pm")
    assert Server.Attention.open_asks() == []
  end

  test "staying on declines: nothing switches and nothing is scheduled", %{ws: ws} do
    {:ok, _} = lobby(ws)
    {:offered, _} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    [ask] = Server.Attention.open_asks()

    assert {:ok, _} = Server.Attention.answer_prompt(ask.id, "andrew", "2")
    assert Shifts.current(ws.id) == "day"
    assert all_enqueued(worker: Server.Jobs.ShiftBack) == []
  end

  test "any number of crews, by any name: each other crew is an option, and a seat goes on any of them",
       %{ws: ws, dahlmann: dahlmann} do
    {:ok, _} = lobby(ws)
    {:ok, _} = Workspaces.seat(ws.id, %{name: "codex-1", archetype: "builder", crew: "codex"})
    assert Shifts.crews(ws.id) == ["codex", "day", "night"]

    assert {:offered, ["codex", "night"]} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    [ask] = Server.Attention.open_asks()
    assert labels(ask) == ["codex crew on", "night crew on", "stay on day"]
    assert {:ok, _} = Server.Attention.answer_prompt(ask.id, "andrew", "1")
    assert Shifts.current(ws.id) == "codex"
    assert names(ws) == ["tertius", "quain", "codex-1"]

    assert {:ok, %{crew: "pi-box"}} = Shifts.assign(dahlmann.id, "pi-box")
    assert {:error, %Ecto.Changeset{}} = Shifts.assign(dahlmann.id, "Not A Crew!")
    assert {:error, :unknown_shift} = Shifts.switch(ws.id, "all")
  end

  test "an offer answered for a crew that has since lost its last seat is refused, and stays open to answer",
       %{ws: ws, dahlmann: dahlmann} do
    {:ok, _} = lobby(ws)
    {:offered, ["night"]} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    [ask] = Server.Attention.open_asks()
    {:ok, _} = Shifts.assign(dahlmann.id, "day")

    assert {:error, :unknown_shift} = Server.Attention.answer_prompt(ask.id, "andrew", "1")
    assert Shifts.current(ws.id) == "day"
    assert [%{id: id}] = Server.Attention.open_asks()
    assert id == ask.id
  end

  test "an open offer is withdrawn when crews switch another way, and its reminder with it", %{ws: ws} do
    {:ok, _} = lobby(ws)
    {:offered, _} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    [ask] = Server.Attention.open_asks()

    {:ok, _} = Shifts.switch(ws.id, "night")
    assert Server.Attention.open_asks() == []
    assert Server.Repo.get!(Server.Message, ask.id).resolution =~ "withdrawn"

    # a taken offer's reminder goes when the operator switches by hand before the reset
    :ok = Shifts.quota_check(ws.id, "hronir", "1/w1", "❯ clear")
    {:ok, _} = Shifts.switch(ws.id, "day")
    {:offered, _} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    [again] = Server.Attention.open_asks()
    {:ok, _} = Server.Attention.answer_prompt(again.id, "andrew", "1")
    assert [_reminder] = all_enqueued(worker: Server.Jobs.ShiftBack)
    {:ok, _} = Shifts.switch(ws.id, "day")
    assert all_enqueued(worker: Server.Jobs.ShiftBack) == []
  end

  test "a limit line is remembered until its pane stops showing it — in the db, so a restart keeps it", %{ws: ws} do
    {:ok, _} = lobby(ws)
    assert {:offered, _} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)

    seen = Server.Repo.get!(Server.Workspace, ws.id).knobs["limits_seen"]
    assert Map.keys(seen) == ["hronir/1/w1"]
    refute seen |> Map.values() |> Enum.any?(&String.contains?(&1, "usage limit"))
    assert :ok = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    assert :ok = Shifts.quota_check(ws.id, "hronir", "2/w2", "❯ clean")

    # the pane moves on: forgotten, so the next limit is a new one, and its offer replaces the old
    assert :ok = Shifts.quota_check(ws.id, "hronir", "1/w1", "❯ carrying on")
    assert Server.Repo.get!(Server.Workspace, ws.id).knobs["limits_seen"] == %{}
    assert {:offered, _} = Shifts.quota_check(ws.id, "hronir", "1/w1", @limit)
    assert [_one] = Server.Attention.open_asks()
  end

  test "the reset time is read off Claude's line, as the next local moment it names; a guess says so" do
    now = ~N[2026-10-09 15:10:00]
    assert Shifts.reset_at("Your limit will reset at 5pm (America/Denver).", now) == {~N[2026-10-09 17:00:00], :exact}
    assert Shifts.reset_at("5-hour limit reached ∙ resets 9:30am", now) == {~N[2026-10-10 09:30:00], :exact}
    assert Shifts.reset_at("weekly limit reached ∙ resets Mon 9:00 AM", now) == {~N[2026-10-12 09:00:00], :exact}
    assert Shifts.reset_at("Weekly limit reached ∙ resets Sunday", now) == {~N[2026-10-11 00:00:00], :estimated}
    assert Shifts.reset_at("limit reached, no time given", now) == {~N[2026-10-09 20:10:00], :estimated}
  end

  test "a reminder cancel that fails is logged, and the switch still goes through", %{ws: ws} do
    {:ok, _} = Shifts.switch(ws.id, "night")
    # no Oban instance: the cancel raises
    :ok = stop_supervised(Oban)

    log = capture_log(fn -> assert {:ok, _} = Shifts.switch(ws.id, "day") end)

    assert log =~ "[warning]"
    assert log =~ "reminder"
    assert log =~ "workspace #{ws.id}"
    assert Shifts.current(ws.id) == "day"
  end

  test "memory for panes no longer there is pruned; an empty read prunes nothing", %{ws: ws} do
    limit = "  ⎿  Claude usage limit reached. Your limit will reset at 5pm (America/Denver)."
    Shifts.quota_check(ws.id, "hronir", "1/w1", limit)
    Shifts.quota_check(ws.id, "hronir", "2/w2", limit)
    :ok = Shifts.prune(ws.id, MapSet.new())
    assert ws.id |> seen_keys() |> length() == 2
    :ok = Shifts.prune(ws.id, MapSet.new(["hronir/2/w2"]))
    assert seen_keys(ws.id) == ["hronir/2/w2"]
  end

  defp seen_keys(ws_id), do: Map.keys(Server.Repo.get!(Server.Workspace, ws_id).knobs["limits_seen"])

  test "only a Claude coworker's pane counts: a pi pane printing the words switches nothing", %{ws: ws} do
    emma = Server.Staff.agent_by_name("emma")
    {:ok, _} = Workspaces.retarget(ws.id, emma.id, %{model: "ollama-cloud/glm-5.2"})
    assert :ok = Shifts.quota_check(ws.id, "emma", "1/w1", "Weekly limit reached ∙ resets Sunday")
    assert Shifts.current(ws.id) == "day"
  end

  test "the day crew rests at night: a manager only on days routes nothing on nights" do
    {:ok, ws2} = Workspaces.register(%{name: "Day manager"})
    {:ok, _} = Workspaces.seat(ws2.id, %{name: "tertius-d", archetype: "surveyor", crew: "day"})
    {:ok, _} = Workspaces.seat(ws2.id, %{name: "night-b", archetype: "builder", crew: "night"})
    assert Workspaces.manager(ws2.id).name == "tertius-d"
    {:ok, _} = Shifts.switch(ws2.id, "night")
    assert Workspaces.manager(ws2.id) == nil
  end

  test "a seat is put on a shift from the board; switching to the shift on changes nothing", %{
    ws: ws,
    dahlmann: dahlmann
  } do
    assert {:ok, %{crew: "all"}} = Shifts.assign(dahlmann.id, "all")
    assert "dahlmann" in names(ws)
    assert {:error, %Ecto.Changeset{}} = Shifts.assign(dahlmann.id, "Dusk Shift")
    assert {:error, :not_found} = Shifts.assign(999_999, "day")

    assert {:ok, %{restaffed: [], waiting: []}} = Shifts.switch(ws.id, "day")
    assert {:error, :unknown_shift} = Shifts.switch(ws.id, "dusk")
  end
end
