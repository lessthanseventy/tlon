defmodule Server.LifeTest do
  use ExUnit.Case, async: true

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
      local = due |> DateTime.to_naive() |> NaiveDateTime.to_erl() |> :calendar.universal_time_to_local_time() |> NaiveDateTime.from_erl!()

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
end
