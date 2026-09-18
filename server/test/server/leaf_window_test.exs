defmodule Server.LeafWindowTest do
  @moduledoc "Human leaf-window names (Slice C): slugging, truncation, collision disambiguation."
  use ExUnit.Case, async: true

  alias Server.LeafWindow

  test "archetype + slugged title" do
    assert LeafWindow.name(:reviewer, "let's review this PR") == "reviewer-let-s-review-this-pr"
  end

  test "a long title truncates on a word boundary, ~24 chars of slug" do
    assert LeafWindow.name(:builder, "implement the per-thread agents design end to end") ==
             "builder-implement-the-per-thread"
  end

  test "a blank or symbol-only title falls back to the bare archetype" do
    assert LeafWindow.name(:planner, "") == "planner"
    assert LeafWindow.name(:planner, "???") == "planner"
    assert LeafWindow.name(:planner, nil) == "planner"
  end

  test "collision gets a -2 disambiguator, next a -3 — only on collision" do
    assert LeafWindow.name(:reviewer, "review", ["reviewer-review"]) == "reviewer-review-2"
    assert LeafWindow.name(:reviewer, "review", ["reviewer-review", "reviewer-review-2"]) == "reviewer-review-3"
    assert LeafWindow.name(:reviewer, "review", ["something-else"]) == "reviewer-review"
  end
end
