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
end
