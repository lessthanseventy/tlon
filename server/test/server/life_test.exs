defmodule Server.LifeTest do
  use ExUnit.Case, async: false

  describe "level/1" do
    test "0 xp is level 0" do
      assert Server.Life.level(0) == 0
    end

    test "just under a boundary stays at the lower level" do
      assert Server.Life.level(99) == 0
      assert Server.Life.level(399) == 1
    end

    test "at a boundary reaches the next level" do
      assert Server.Life.level(100) == 1
      assert Server.Life.level(400) == 2
    end
  end

  describe "next_level_at/1" do
    test "the absolute xp threshold for the next level" do
      assert Server.Life.next_level_at(0) == 100
      assert Server.Life.next_level_at(100) == 400
      assert Server.Life.next_level_at(399) == 400
    end
  end

  describe "current_due_at/2" do
    test "the most recent occurrence at or before now" do
      created = DateTime.new!(~D[2026-01-01], ~T[00:00:00], "Etc/UTC")
      routine = %Server.Routine{every: "0 9 * * *", created_at: created}
      now = DateTime.new!(~D[2026-01-05], ~T[12:00:00], "Etc/UTC")

      due = Server.Life.current_due_at(routine, now)

      local =
        due
        |> DateTime.to_naive()
        |> NaiveDateTime.to_erl()
        |> :calendar.universal_time_to_local_time()
        |> NaiveDateTime.from_erl!()

      assert local.hour == 9
      assert DateTime.compare(due, now) != :gt
    end

    test "nil before the routine's first occurrence" do
      created = DateTime.new!(~D[2026-01-05], ~T[10:00:00], "Etc/UTC")
      routine = %Server.Routine{every: "0 9 * * *", created_at: created}
      now = DateTime.new!(~D[2026-01-05], ~T[11:00:00], "Etc/UTC")

      assert Server.Life.current_due_at(routine, now) == nil
    end
  end

  describe "xp/1" do
    setup do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "life-xp-#{System.unique_integer()}", type: "home"})

      {:ok, routine} =
        %{workspace_id: ws.id, title: "stretch", every: "@daily"}
        |> Server.Routine.create_changeset()
        |> Server.Repo.insert()

      %{ws: ws, routine: routine}
    end

    test "on-time runs count full xp, late runs count half, quests add their own", %{ws: ws, routine: routine} do
      due = DateTime.truncate(DateTime.utc_now(), :second)
      insert_run!(routine, due, done_at: due, late: false)
      insert_run!(routine, DateTime.add(due, -86_400), done_at: DateTime.add(due, -86_400), late: true)

      {:ok, quest} =
        %{workspace_id: ws.id, title: "dentist", xp: 20} |> Server.Quest.create_changeset() |> Server.Repo.insert()

      quest |> Server.Quest.done_changeset(DateTime.utc_now()) |> Server.Repo.update!()

      # routine.xp defaults to 10: 10 (on time) + 5 (late, integer div) + 20 (quest) = 35
      assert Server.Life.xp(ws.id) == 35
    end

    defp insert_run!(routine, due_at, done_at: done_at, late: late) do
      %{routine_id: routine.id, due_at: due_at, done_at: done_at, late: late}
      |> Server.RoutineRun.create_changeset()
      |> Server.Repo.insert!()
    end
  end

  describe "late?/3" do
    test "on time at the boundary" do
      due = ~U[2026-01-01 09:00:00Z]
      refute Server.Life.late?(due, DateTime.add(due, 60 * 60), 60)
    end

    test "late one second past the window" do
      due = ~U[2026-01-01 09:00:00Z]
      assert Server.Life.late?(due, DateTime.add(due, 60 * 60 + 1), 60)
    end
  end

  describe "streak/2" do
    setup do
      Server.TestDB.clean!()
      created = ~U[2026-01-01 00:00:00Z]

      {:ok, routine} =
        %{workspace_id: register_ws!().id, title: "stretch", every: "0 9 * * *"}
        |> Server.Routine.create_changeset()
        |> Ecto.Changeset.force_change(:created_at, created)
        |> Server.Repo.insert()

      %{routine: routine}
    end

    test "counts back from now, stopping at the first totally-missed due", %{routine: routine} do
      created = ~U[2026-01-01 00:00:00Z]
      dues = Enum.scan(1..7, created, fn _, cursor -> Server.Schedules.next_occurrence(routine.every, cursor) end)
      # 7 daily occurrences after created. Run all but the 4th (the gap).
      for due <- List.delete_at(dues, 3), do: insert_run!(routine, due, done_at: due, late: false)

      now = DateTime.add(List.last(dues), 3600)

      assert Server.Life.streak(routine, now) == 3
    end

    defp register_ws!,
      do: %{name: "life-streak-#{System.unique_integer()}", type: "home"} |> Server.Workspaces.register() |> elem(1)
  end

  describe "routine_done/2" do
    setup do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "life-done-#{System.unique_integer()}", type: "home"})

      {:ok, routine} =
        %{workspace_id: ws.id, title: "stretch", every: "@daily", xp: 2}
        |> Server.Routine.create_changeset()
        |> Ecto.Changeset.force_change(
          :created_at,
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-90_000, :second)
        )
        |> Server.Repo.insert()

      %{ws: ws, routine: routine}
    end

    test "stamps a run and reports level_up only on the crossing stamp", %{ws: ws, routine: routine} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      {:ok, pad} =
        %{workspace_id: ws.id, title: "pad", xp: 99} |> Server.Quest.create_changeset() |> Server.Repo.insert()

      pad |> Server.Quest.done_changeset(now) |> Server.Repo.update!()

      {:ok, _run, level_up} = Server.Life.routine_done(routine.id, now)
      assert level_up == true

      assert Server.Life.routine_done(routine.id, now) == {:error, :already_done}
    end

    test "a second stamp of the same instance is refused, not a second run", %{routine: routine} do
      now = DateTime.truncate(DateTime.utc_now(), :second)
      assert {:ok, _run, _} = Server.Life.routine_done(routine.id, now)
      assert Server.Life.routine_done(routine.id, now) == {:error, :already_done}
    end
  end

  describe "status/1" do
    setup do
      Server.TestDB.clean!()
      :ok
    end

    test "assembles xp, level, next_level_at, streaks, due, quests, today" do
      {:ok, ws} = Server.Workspaces.register(%{name: "life-status-#{System.unique_integer()}", type: "home"})
      {:ok, routine} = Server.Life.create_routine(ws.id, %{title: "stretch", every: "@daily"})
      {:ok, _quest} = Server.Life.create_quest(ws.id, %{title: "dentist"})

      status = Server.Life.status(ws.id)

      assert status.xp == 0
      assert status.level == 0
      assert status.next_level_at == 100
      assert Map.has_key?(status.streaks, routine.id)
      assert is_list(status.due)
      assert is_list(status.quests)
      assert is_list(status.today)
    end
  end
end
