defmodule Console.PresenceTest do
  @moduledoc "Presence/typing derivation from a tmux window snapshot — pure, now is an argument."
  use ExUnit.Case, async: true

  alias Console.Presence

  @now 1_000_000

  test "parse_windows: name + thread tag + activity; blanks nil; malformed lines drop" do
    out = "tertius\t\t#{@now}\nplanner-fix\t7\t#{@now - 60}\nt9\t\t\n\n"

    assert Presence.parse_windows(out) == [
             %{name: "tertius", thread_id: nil, activity: @now},
             %{name: "planner-fix", thread_id: 7, activity: @now - 60},
             %{name: "t9", thread_id: nil, activity: nil}
           ]
  end

  test "thread_status: recent activity → working; stale → live; no window → none; legacy t<id> matches" do
    windows = [
      %{name: "planner-fix", thread_id: 7, activity: @now - 3},
      %{name: "reviewer-old", thread_id: 8, activity: @now - 300},
      %{name: "t9", thread_id: nil, activity: @now - 1}
    ]

    assert Presence.thread_status(windows, 7, @now) == :working
    assert Presence.thread_status(windows, 8, @now) == :live
    assert Presence.thread_status(windows, 9, @now) == :working
    assert Presence.thread_status(windows, 42, @now) == :none
  end

  test "coworker_seat: the busiest of the standing window and any led leaf, with its thread" do
    windows = [
      %{name: "vera", thread_id: nil, activity: @now - 500},
      %{name: "reviewer-hot", thread_id: 12, activity: @now - 2}
    ]

    assert Presence.coworker_seat(windows, "vera", [12], @now) == {:working, 12}
    assert Presence.coworker_seat(windows, "vera", [], @now) == {:live, nil}
    assert Presence.coworker_seat([], "vera", [], @now) == {:none, nil}
  end

  test "working_count counts distinct active windows" do
    windows = [
      %{name: "a", thread_id: nil, activity: @now - 1},
      %{name: "b", thread_id: nil, activity: @now - 100}
    ]

    assert Presence.working_count(windows, @now) == 1
  end

  describe "started_s/1 — funes time normalized to unix seconds at the TUI boundary" do
    test "a funes DateTime becomes unix seconds (the live crash shape: int - DateTime)" do
      at = ~U[2026-08-28 04:22:31Z]
      assert Presence.started_s(at) == DateTime.to_unix(at)
    end

    test "an already-unix integer passes through" do
      assert Presence.started_s(1_787_890_951) == 1_787_890_951
    end
  end
end
