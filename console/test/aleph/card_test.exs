defmodule Console.CardTest do
  # The Slice-D visual system's shared primitives: colour resolvers + the two card shapes.
  use ExUnit.Case, async: true

  alias Console.Card

  describe "colour resolvers" do
    test "status_color maps the signal tier; unknown → :dim" do
      assert Card.status_color(:working) == :st_working
      assert Card.status_color(:failing) == :st_blocked
      assert Card.status_color(:awaiting) == :st_await
      assert Card.status_color(:done) == :st_done
      assert Card.status_color(:idle) == :st_idle
      assert Card.status_color(:whatever) == :dim
    end

    test "archetype_color maps identity hues, atom or string" do
      assert Card.archetype_color(:surveyor) == :arch_surveyor
      assert Card.archetype_color("builder") == :arch_builder
      assert Card.archetype_color(:reviewer) == :arch_reviewer
      assert Card.archetype_color(:nope) == :normal
    end

    test "workspace_hue prefers an explicit knob, else cycles by id, stable per workspace" do
      assert Card.workspace_hue(%{knobs: %{"hue" => "arch_planner"}}) == :arch_planner
      hue = Card.workspace_hue(%{id: 2})
      assert hue in [:arch_surveyor, :arch_builder, :arch_reviewer, :arch_planner, :arch_assistant]
      assert Card.workspace_hue(%{id: 2}) == hue
      assert Card.workspace_hue(%{}) == :accent
    end

    test "status_dot is a filled dot in the status colour" do
      assert Card.status_dot(:blocked) == {"●", :st_blocked}
    end
  end

  describe "gutter_card/3" do
    test "opens with a status-coloured gutter run; body rows indent under it" do
      [header | body] = Card.gutter_card([{"a ticket", :normal}], [[{"detail", :dim}]], :working)

      assert [{"▌ ", :st_working}, {"a ticket", :normal}] = header
      assert [[{"  ", :normal}, {"detail", :dim}]] = body
    end

    test "a folded card is a single row (no body)" do
      assert [[{"▌ ", :st_open}, {"just a header", :normal}]] = Card.gutter_card([{"just a header", :normal}])
    end
  end

  describe "boxed_card/4" do
    test "frames a title + body in status-coloured box-drawing chars, w wide" do
      [top | rest] = Card.boxed_card("ficciones", [[{"3 open", :dim}]], 24, :open)
      {body, [bottom]} = Enum.split(rest, -1)

      # top border carries the title and opens/closes with the frame corners
      assert [{"╭─ ", :st_open}, {"ficciones", :label} | _] = top
      assert List.last(top) == {"╮", :st_open}
      # each body row is framed left+right
      assert [[{"│ ", :st_open} | _] = row] = body
      assert List.last(row) == {" │", :st_open}
      # bottom is a single frame rule
      assert [{"╰" <> _, :st_open}] = bottom
    end

    test "a title too wide for the box is truncated, not overflowed" do
      [top | _] = Card.boxed_card("a very long workspace name indeed", [], 12, :done)
      title = Enum.at(top, 1) |> elem(0)
      assert String.length(title) <= 12
    end
  end
end
