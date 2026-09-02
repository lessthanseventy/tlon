defmodule Console.DeliveryTest do
  @moduledoc """
  `delivery_target/3` — THE routing decision for a posted message — driven through the same
  `:tlon_cmd` seam the spawn suites use, against the one-workspace fixture (surveyor `tertius` =
  meta, builder `hronir` = worker). `standing_thread_id` is set so no server read is needed.
  """
  use ExUnit.Case, async: false

  alias Console.Delivery

  setup do
    Console.TestWorkspaces.put()
    on_exit(fn -> Application.delete_env(:console, :tlon_cmd) end)
    :ok
  end

  defp windows(out) do
    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      if "list-windows" in args, do: {out, 0}, else: {"", 0}
    end)
  end

  defp state(overrides \\ %{}),
    do: Map.merge(%{active_key: 0, standing_thread_id: 1, opening_injected: MapSet.new()}, overrides)

  describe "delivery_target/3" do
    test "the standing coworker's own thread routes globally" do
      assert Delivery.delivery_target(%{thread_id: 1}, state(), "hronir-machine") == {:route, nil}
    end

    test "no lead, or a meta (surveyor) lead, routes globally — there is no leaf window to redirect onto" do
      assert Delivery.delivery_target(%{thread_id: 2}, state(), nil) == {:route, nil}
      assert Delivery.delivery_target(%{thread_id: 2}, state(), "tertius-machine") == {:route, nil}
    end

    test "a worker-led thread whose leaf is live and past its opening turn routes onto that window" do
      windows("1\t0\ttertius\t\t\n0\t1\tbuilder-fix\t2\tdone\n")
      assert Delivery.delivery_target(%{thread_id: 2}, state(), "hronir-machine") == {:route, "builder-fix"}
    end

    test "a worker-led thread mid-spawn (no window yet) or pre-opening (typed, not submitted) is skipped" do
      windows("1\t0\ttertius\t\t\n")
      assert Delivery.delivery_target(%{thread_id: 2}, state(), "hronir-machine") == :skip

      windows("1\t0\ttertius\t\t\n0\t1\tbuilder-fix\t2\ttyped\n")
      assert Delivery.delivery_target(%{thread_id: 2}, state(), "hronir-machine") == :skip
    end

    test "process memory of a submitted opening (opening_injected) also counts as past it" do
      windows("1\t0\ttertius\t\t\n0\t1\tbuilder-fix\t2\t\n")
      st = state(%{opening_injected: MapSet.new([2])})
      assert Delivery.delivery_target(%{thread_id: 2}, st, "hronir-machine") == {:route, "builder-fix"}
    end

    test "a row without a thread routes globally" do
      assert Delivery.delivery_target(%{}, state(), "hronir-machine") == {:route, nil}
    end
  end

  describe "staffed_leaf_window/3 (pure)" do
    @tabs [
      %{name: "tertius", active?: true, index: "0", thread_id: nil, opening: nil, activity: nil},
      %{name: "builder-fix", active?: false, index: "1", thread_id: 2, opening: "done", activity: nil},
      %{name: "t3", active?: false, index: "2", thread_id: nil, opening: nil, activity: nil}
    ]

    test "resolves by tag (done) or by process memory; nil otherwise" do
      assert Delivery.staffed_leaf_window(2, @tabs, MapSet.new()) == "builder-fix"
      assert Delivery.staffed_leaf_window(3, @tabs, MapSet.new()) == nil
      assert Delivery.staffed_leaf_window(3, @tabs, MapSet.new([3])) == "t3"
      assert Delivery.staffed_leaf_window(9, @tabs, MapSet.new([9])) == nil
    end
  end
end
