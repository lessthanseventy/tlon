defmodule Console.Panel.CrewTest do
  @moduledoc "The CREW pane: pure assembly (roster ⋈ windows ⋈ leads ⋈ thinking) + render."
  use ExUnit.Case, async: true

  alias Console.Panel.Crew

  defp texts(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, "", fn {t, _s} -> t end) end)

  describe "coworkers/6" do
    @now 1_000_000
    @roster [
      %Server.Coworker{archetype: "surveyor", name: "tertius"},
      %Server.Coworker{archetype: "builder", name: "hronir"}
    ]
    @titles %{7 => "fix the bug", 9 => "write the doc"}

    defp by_name(coworkers, name), do: Enum.find(coworkers, &(&1.name == name))

    test "a coworker with no window is off; a quiet window is idle" do
      windows = [%{name: "tertius", thread_id: nil, activity: @now - 600}]
      coworkers = Crew.coworkers(@roster, windows, %{}, @titles, %{}, @now)

      assert %{status: :live, seat: nil, archetype: :surveyor} = by_name(coworkers, "tertius")
      assert %{status: :none, seat: nil} = by_name(coworkers, "hronir")
    end

    test "recent activity on a led leaf reads as working, seated on that thread" do
      windows = [
        %{name: "hronir", thread_id: nil, activity: @now - 600},
        %{name: "t7", thread_id: 7, activity: @now - 2}
      ]

      coworkers = Crew.coworkers(@roster, windows, %{"hronir" => [7]}, @titles, %{}, @now)

      assert %{status: :working, seat: "fix the bug"} = by_name(coworkers, "hronir")
    end

    test "a declared thinking beats the tmux inference and seats the declared thread" do
      windows = [%{name: "hronir", thread_id: nil, activity: @now - 2}]
      thinking = %{9 => %{"hronir" => @now - 1}}

      coworkers = Crew.coworkers(@roster, windows, %{}, @titles, thinking, @now)

      assert %{status: :thinking, seat: "write the doc", elapsed_s: 1} = by_name(coworkers, "hronir")
    end

    test "a non-thinking coworker carries no elapsed_s" do
      windows = [%{name: "tertius", thread_id: nil, activity: @now - 600}]
      coworkers = Crew.coworkers(@roster, windows, %{}, @titles, %{}, @now)

      assert %{status: :live, elapsed_s: nil} = by_name(coworkers, "tertius")
    end

    test "profile fields ride along; an unknown archetype drops" do
      roster = @roster ++ [%Server.Coworker{archetype: "gardener", name: "x"}]
      coworkers = Crew.coworkers(roster, [], %{}, %{}, %{}, @now)

      assert length(coworkers) == 2
      assert %{harness: harness, model: _model} = by_name(coworkers, "hronir")
      assert harness
    end
  end

  test "live-count header + per-coworker archetype, presence, seat, and driver" do
    data = %{
      leaves: {2, 6},
      coworkers: [
        %{name: "tertius", archetype: :surveyor, model: %{model: "glm-5.2"}, harness: :pi, status: :live, seat: nil},
        %{
          name: "vera",
          archetype: :reviewer,
          model: %{model: "claude-sonnet-5"},
          harness: :claude_code,
          status: :working,
          seat: "fix the bug"
        }
      ]
    }

    body = texts(Crew.render(data, %{x: 0, y: 0, w: 26, h: 30}))

    assert Enum.at(body, 0) =~ "2/6 live"
    assert Enum.any?(body, &(&1 =~ "tertius" and &1 =~ "surveyor"))
    assert Enum.any?(body, &(&1 =~ "idle"))
    assert Enum.any?(body, &(&1 =~ "working" and &1 =~ "fix the bug"))
    assert Enum.any?(body, &(&1 =~ "glm-5.2" and &1 =~ "pi"))
    assert Enum.any?(body, &(&1 =~ "claude-sonnet-5" and &1 =~ "· claude"))
  end

  test "a declared thinking renders the ⋯ glyph in accent" do
    data = %{
      leaves: {0, 6},
      coworkers: [
        %{
          name: "hronir",
          archetype: :builder,
          model: nil,
          harness: :claude_code,
          status: :thinking,
          seat: "write the doc"
        }
      ]
    }

    rendered = Crew.render(data, %{x: 0, y: 0, w: 26, h: 30})
    body = texts(rendered)

    assert Enum.any?(body, &(&1 =~ "⋯" and &1 =~ "thinking" and &1 =~ "write the"))
    accents = rendered |> Enum.flat_map(& &1) |> Enum.filter(fn {_t, s} -> s == :accent end)
    assert Enum.any?(accents, fn {t, _s} -> t =~ "⋯" end)
  end

  # The elapsed clock is the trust signal (funes thread #3, 2026-08-27): a coworker that's been
  # "thinking" for a while must visibly count up, not just sit on a static word that reads as
  # frozen during a long single turn.
  test "a declared thinking with elapsed_s appends a ticking duration" do
    data = %{
      leaves: {0, 6},
      coworkers: [
        %{
          name: "hronir",
          archetype: :builder,
          model: nil,
          harness: :claude_code,
          status: :thinking,
          seat: "write the doc",
          elapsed_s: 192
        }
      ]
    }

    body = texts(Crew.render(data, %{x: 0, y: 0, w: 40, h: 30}))
    assert Enum.any?(body, &(&1 =~ "thinking 3m12s"))
  end

  test "no elapsed_s (nil, or the key absent) appends nothing" do
    coworker = %{
      name: "tertius",
      archetype: :surveyor,
      model: nil,
      harness: :pi,
      status: :live,
      seat: nil,
      elapsed_s: nil
    }

    data = %{leaves: {0, 6}, coworkers: [coworker]}
    body = texts(Crew.render(data, %{x: 0, y: 0, w: 40, h: 30}))
    assert Enum.any?(body, &(&1 =~ "idle"))
    refute Enum.any?(body, &(&1 =~ ~r/idle\s*\d/))
  end

  test "rows clip to the rect" do
    coworkers =
      for i <- 1..20 do
        %{name: "cw#{i}", archetype: :builder, model: nil, harness: :pi, status: :none, seat: nil}
      end

    rendered = Crew.render(%{leaves: {0, 6}, coworkers: coworkers}, %{x: 0, y: 0, w: 12, h: 8})
    assert length(rendered) <= 8
    assert Enum.all?(texts(rendered), &(String.length(&1) <= 12))
  end

  test "nil data renders nothing" do
    assert Crew.render(nil, %{x: 0, y: 0, w: 20, h: 10}) == []
  end
end
