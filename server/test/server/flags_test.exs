defmodule Server.FlagsTest do
  # `Server.Flags` — the server's feature flags (fun_with_flags on the store's Postgres).
  use ExUnit.Case, async: false

  alias Server.Flags

  setup do
    Server.TestDB.clean!()
  end

  test "a flag nobody flipped is off, and the office map says so" do
    refute Flags.enabled?(:build_mode)
    assert Flags.office() == %{build_mode: false}
  end

  test "set/2 flips a flag on and off by name" do
    assert {:ok, %{name: :build_mode, enabled: true}} = Flags.set("build_mode", true)
    assert Flags.enabled?(:build_mode)
    assert Flags.office() == %{build_mode: true}

    assert {:ok, %{name: :build_mode, enabled: false}} = Flags.set("build_mode", false)
    refute Flags.enabled?(:build_mode)
  end

  test "a name the server has no flag for is refused, never created" do
    assert {:error, "no flag named nope" <> _} = Flags.set("nope", true)
    assert Server.Repo.aggregate("fun_with_flags_toggles", :count) == 0
  end

  test "the office snapshot carries the flags" do
    {:ok, _} = Flags.set("build_mode", true)
    assert Server.Office.status().flags == %{build_mode: true}
  end
end
