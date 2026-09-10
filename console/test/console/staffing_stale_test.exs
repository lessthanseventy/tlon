defmodule Console.StaffingStaleTest do
  @moduledoc """
  A coworker whose identity went stale: a rename on the server leaves the live process minting
  under a handle the agent table no longer has, so every `post_message` 400s while the WINDOW name
  still looks perfectly correct (2026-09-09: `tertius-machine` after the `-machine` retirement).
  The staffing pass tears those down so they respawn; it must never touch a healthy one.
  """
  use ExUnit.Case, async: true

  alias Console.Staffing

  defp tab(name, author),
    do: {%{name: name, active?: false, index: name, thread_id: nil, opening: nil, activity: nil, pane_pid: 1}, author}

  defp check(pairs, bench) do
    tabs = Enum.map(pairs, &elem(&1, 0))
    authors = Map.new(pairs, fn {t, a} -> {t.name, a} end)

    Staffing.stale_coworkers(tabs, bench, fn t -> authors[t.name] end)
  end

  test "a process holding a handle the bench no longer has is stale" do
    stale = check([tab("tertius", "tertius-machine")], ["tertius", "hronir"])

    assert [%{name: "tertius"}] = stale
  end

  test "a process whose handle IS on the bench is left alone" do
    assert check([tab("hronir", "hronir")], ["tertius", "hronir"]) == []
  end

  test "an unreadable process is never stale — we do not kill what we could not identify" do
    assert check([tab("hronir", nil)], ["someone-else"]) == []
  end

  test "the window NAME is not the test — only the identity the process actually holds" do
    # the name matches the bench exactly; the env underneath does not. This is the whole bug.
    assert [%{name: "hronir"}] = check([tab("hronir", "hronir-machine")], ["hronir"])
  end

  test "several stale coworkers all come back" do
    stale = check([tab("tertius", "tertius-machine"), tab("hronir", "hronir-machine")], ["tertius", "hronir"])

    assert Enum.map(stale, & &1.name) == ["tertius", "hronir"]
  end

  test "pane_author is nil for a pid that cannot be read, never a crash" do
    assert Staffing.pane_author(%{pane_pid: 999_999_999}) == nil
    assert Staffing.pane_author(%{pane_pid: nil}) == nil
    assert Staffing.pane_author(%{}) == nil
  end
end
