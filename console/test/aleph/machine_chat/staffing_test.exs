defmodule Console.MachineChat.StaffingTest do
  @moduledoc """
  The pure pick for who gets staffed as a new chat thread's lead: the composer text's first
  @-mentioned coworker, else the configured default. Pulled out of `Loop` (which grabs the TTY)
  so it tests without one.
  """
  use ExUnit.Case, async: true

  alias Console.MachineChat.Staffing

  @roster [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "builder", "name" => "hronir"}]

  test "the first @-mentioned coworker wins over the default" do
    assert Staffing.pick_coworker("@tertius-machine do x", "hronir-machine", @roster) == "tertius-machine"
  end

  test "no mention falls back to the default" do
    assert Staffing.pick_coworker("no mention", "hronir-machine", @roster) == "hronir-machine"
  end

  test "a non-coworker @-handle is ignored — falls back to the default" do
    assert Staffing.pick_coworker("@andrew hi", "hronir-machine", @roster) == "hronir-machine"
  end

  test "an empty roster (funes-down) falls back to the default even with a mention" do
    assert Staffing.pick_coworker("@tertius-machine do x", "hronir-machine") == "hronir-machine"
  end

  # Slice E: intent triage sits between the mention fast path and the static default.
  describe "pick_coworker/3 with triage" do
    @cast @roster ++ [%{"archetype" => "reviewer", "name" => "vera"}]

    test "unrouted review intent staffs the roster's reviewer, not the default" do
      assert Staffing.pick_coworker("review the staffing diff", "hronir-machine", @cast) == "vera-machine"
    end

    test "an @-mention still wins over intent — no classification hop on the fast path" do
      assert Staffing.pick_coworker("@hronir-machine review the diff", "x-machine", @cast) == "hronir-machine"
    end

    test "intent with no matching roster worker falls through to the default" do
      assert Staffing.pick_coworker("research the eviction policy", "hronir-machine", @cast) == "hronir-machine"
    end
  end

  describe "route_reason/3 — the staffing note's why" do
    @cast2 [%{"archetype" => "builder", "name" => "hronir"}, %{"archetype" => "reviewer", "name" => "vera"}]

    test "a named coworker → :mention; intent → :triage; else :default" do
      assert Staffing.route_reason("@vera-machine check this", "vera-machine", @cast2) == :mention
      assert Staffing.route_reason("review the diff", "vera-machine", @cast2) == :triage
      assert Staffing.route_reason("build the thing", "hronir-machine", @cast2) == :default
    end
  end

  describe "default_coworker/1 — the roster-derived default (no @-mention path)" do
    # The regression seam: the machine-chat beam has no `Console.Workspaces` cache, so it must derive the
    # default from the LIVE funes roster — never a stale stand-in whose `-machine` handle was never
    # registered as a funes agent (the leaderless-thread silence bug).
    test "picks the roster's builder as its -machine handle" do
      assert Staffing.default_coworker(@roster) == "hronir-machine"
    end

    # Slice B (per-thread-agents): the default is WORKER-only — tertius is the vantage, never a
    # leaf lead. A builder-less roster picks its first worker instead.
    test "a builder-less roster picks its first WORKER, skipping the meta surveyor" do
      roster = [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "planner", "name" => "borges"}]
      assert Staffing.default_coworker(roster) == "borges-machine"
    end

    test "a worker-less (surveyor-only) roster yields nil — a misconfiguration to surface, not a meta lead" do
      assert Staffing.default_coworker([%{"archetype" => "surveyor", "name" => "tertius"}]) == nil
    end

    test "an empty roster yields nil — never a guessed handle that was never registered" do
      assert Staffing.default_coworker([]) == nil
    end
  end
end
