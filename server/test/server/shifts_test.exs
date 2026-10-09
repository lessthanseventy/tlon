defmodule Server.ShiftsTest do
  # Day and night shifts on one bench: a seat is on the day shift, the night shift, or both (`all`,
  # every seat until it is put on one). Only the crew on shift is the bench staffing sees, so a
  # workspace with no shifts set works as it always has. A shift change restaffs a workline led by
  # someone going off the workline's own way; a plain thread waits for its lead's shift.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Shifts
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Shifts"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius", archetype: "surveyor"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder", crew: "day"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "emma", archetype: "builder", crew: "day"})
    {:ok, dahlmann} = Workspaces.seat(ws.id, %{name: "dahlmann", archetype: "builder", crew: "night"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "quain", archetype: "librarian"})
    %{ws: ws, dahlmann: dahlmann}
  end

  defp names(ws), do: ws.id |> Workspaces.bench() |> Enum.map(& &1.name)

  test "a workspace with no shifts set: every seat is on, either shift" do
    {:ok, plain} = Workspaces.register(%{name: "Plain"})
    {:ok, _} = Workspaces.seat(plain.id, %{name: "solo", archetype: "builder"})
    assert names(plain) == ["solo"]
    assert {:ok, _} = Shifts.switch(plain.id, "night")
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
    assert built |> Channel.thread_messages() |> Enum.any?(&(&1.body =~ "night shift is on"))
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

  test "a seat is put on a shift from the board; switching to the shift on changes nothing", %{
    ws: ws,
    dahlmann: dahlmann
  } do
    assert {:ok, %{crew: "all"}} = Shifts.assign(dahlmann.id, "all")
    assert "dahlmann" in names(ws)
    assert {:error, %Ecto.Changeset{}} = Shifts.assign(dahlmann.id, "dusk")
    assert {:error, :not_found} = Shifts.assign(999_999, "day")

    assert {:ok, %{restaffed: [], waiting: []}} = Shifts.switch(ws.id, "day")
    assert {:error, :unknown_shift} = Shifts.switch(ws.id, "dusk")
  end
end
