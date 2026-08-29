defmodule Console.MentionTest do
  @moduledoc """
  The @-mention router — who gets woken, and what they're shown. Pure: the cockpit edge does the
  tmux send-keys. The loop guard (never echo back to the sender) and the handle→window mapping are
  the two things that must not regress.
  """
  use ExUnit.Case, async: true

  alias Console.Mention

  # The seed roster (Console.Space's fallback Tlön workspace) — the fixture every roster-derived test
  # below threads through mentions/route instead of a compile-time @base_coworkers. The builder's
  # handle is "hronir-machine" (post-C2.3 rename), NOT the legacy "claude-machine".
  @roster [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "builder", "name" => "hronir"}]

  test "the handle -> window map is derived from the roster, not a compile-time table" do
    assert Mention.mentions("@hronir-machine ping", @roster) == [{"hronir-machine", "hronir"}]
  end

  test "an @-handle maps to its coworker window" do
    assert Mention.mentions("@hronir-machine check MCP", @roster) == [{"hronir-machine", "hronir"}]
    assert Mention.mentions("hey @tertius-machine", @roster) == [{"tertius-machine", "tertius"}]
  end

  test "a non-coworker @-handle is ignored (slack-style noise, not a route)" do
    assert Mention.mentions("@andrew nope", @roster) == []
    assert Mention.mentions("@pi-machine gone", @roster) == []
  end

  test "an empty roster resolves nothing (funes-down degrades to no wakes)" do
    assert Mention.mentions("@hronir-machine ping", []) == []
  end

  test "multiple mentions dedupe and keep first-seen order" do
    assert Mention.mentions("@hronir-machine @tertius-machine @hronir-machine", @roster) ==
             [{"hronir-machine", "hronir"}, {"tertius-machine", "tertius"}]
  end

  test "route wakes every mentioned coworker EXCEPT the author's own window (loop guard)" do
    assert Mention.route(%{author: "tertius-machine", body: "@hronir-machine check MCP", thread_id: 1}, [], @roster) ==
             [{"hronir", "[tlon thread #1] tertius-machine: @hronir-machine check MCP"}]

    assert Mention.route(%{author: "hronir-machine", body: "@tertius-machine your turn", thread_id: 1}, [], @roster) ==
             [{"tertius", "[tlon thread #1] hronir-machine: @tertius-machine your turn"}]
  end

  test "the operator (not a coworker) mentioning the builder wakes it" do
    assert Mention.route(%{author: "andrew", body: "@hronir-machine do the thing", thread_id: 7}, [], @roster) ==
             [{"hronir", "[tlon thread #7] andrew: @hronir-machine do the thing"}]
  end

  test "a multiline body is flattened to one line (tmux send-keys is line-based)" do
    routed = Mention.route(%{author: "andrew", body: "@hronir-machine line one\nline two", thread_id: 1}, [], @roster)
    assert [{_window, text}] = routed
    assert text == "[tlon thread #1] andrew: @hronir-machine line one line two"
  end

  test "a message with no mention routes nowhere" do
    assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 1}, [], @roster) == []
  end

  test "a message missing thread_id still routes (with '?' for the id)" do
    assert Mention.route(%{author: "andrew", body: "@hronir-machine hi", thread_id: nil}, [], @roster) ==
             [{"hronir", "[tlon thread ?] andrew: @hronir-machine hi"}]
  end

  describe "route/3 with a thread lead (bare-reply wake)" do
    test "a bare reply (no @-mention) wakes the thread's lead coworker" do
      assert Mention.route(
               %{author: "andrew", body: "who am i talking to?", thread_id: 9},
               [lead: "hronir-machine"],
               @roster
             ) == [{"hronir", "[tlon thread #9] andrew: who am i talking to?"}]
    end

    test "an explicit @-mention overrides the lead (directed, not the lead)" do
      assert Mention.route(
               %{author: "andrew", body: "@tertius-machine you take this", thread_id: 9},
               [lead: "hronir-machine"],
               @roster
             ) == [{"tertius", "[tlon thread #9] andrew: @tertius-machine you take this"}]
    end

    test "the lead is not woken by its own post (loop guard still holds)" do
      assert Mention.route(
               %{author: "hronir-machine", body: "thinking out loud", thread_id: 9},
               [lead: "hronir-machine"],
               @roster
             ) == []
    end

    test "no lead and no mention wakes nobody (unchanged)" do
      assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 9}, [lead: nil], @roster) == []
    end

    test "an unknown lead handle (not a coworker window) wakes nobody" do
      assert Mention.route(%{author: "andrew", body: "hi", thread_id: 9}, [lead: "ghost"], @roster) == []
    end

    test "route/1 is unchanged (no lead = old behaviour)" do
      assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 1}) == []

      assert Mention.route(%{author: "andrew", body: "@hronir-machine hi", thread_id: 7}, [], @roster) ==
               [{"hronir", "[tlon thread #7] andrew: @hronir-machine hi"}]
    end
  end

  describe "route/3 with a staffed per-thread window (B1.4)" do
    test "a bare reply on a staffed thread wakes ITS t<id> window, not the standing coworker" do
      assert Mention.route(
               %{author: "andrew", body: "tell me a joke", thread_id: 2},
               [lead: "hronir-machine", staffed_window: "t2"],
               @roster
             ) == [{"t2", "[tlon thread #2] andrew: tell me a joke"}]
    end

    test "an explicit @-mention of the lead on a staffed thread also lands on t<id>" do
      assert Mention.route(
               %{author: "andrew", body: "@hronir-machine ping", thread_id: 2},
               [lead: "hronir-machine", staffed_window: "t2"],
               @roster
             ) == [{"t2", "[tlon thread #2] andrew: @hronir-machine ping"}]
    end

    test "the staffed lead's own post wakes nobody (loop guard survives the redirect)" do
      assert Mention.route(
               %{author: "hronir-machine", body: "thinking out loud", thread_id: 2},
               [lead: "hronir-machine", staffed_window: "t2"],
               @roster
             ) == []
    end

    test "a mention of a DIFFERENT coworker is not redirected (only the lead's window moves)" do
      assert Mention.route(
               %{author: "andrew", body: "@tertius-machine you take it", thread_id: 2},
               [lead: "hronir-machine", staffed_window: "t2"],
               @roster
             ) == [{"tertius", "[tlon thread #2] andrew: @tertius-machine you take it"}]
    end

    test "nil staffed_window is the standing-thread path (no redirect)" do
      assert Mention.route(
               %{author: "andrew", body: "tell me a joke", thread_id: 1},
               [lead: "hronir-machine", staffed_window: nil],
               @roster
             ) == [{"hronir", "[tlon thread #1] andrew: tell me a joke"}]
    end
  end

  describe "crew role resolution (per-thread windows)" do
    test "@reviewer-machine on a thread routes to that thread's r<id> window" do
      row = %{author: "hronir-machine", body: "@reviewer-machine review the diff in HEAD~1", thread_id: 42}

      assert Mention.route(row, [lead: "hronir-machine", staffed_window: "t42"], @roster) ==
               [{"r42", "[tlon thread #42] hronir-machine: @reviewer-machine review the diff in HEAD~1"}]
    end

    test "a reviewer's own post never wakes its own r<id> window (loop guard)" do
      row = %{author: "reviewer-machine", body: "@reviewer-machine note to self", thread_id: 42}
      assert Mention.route(row, [lead: "hronir-machine", staffed_window: "t42"], @roster) == []
    end

    test "reviewer ESCALATE to the leader lands on the leader's staffed window" do
      row = %{author: "reviewer-machine", body: "@hronir-machine ESCALATE apply: <patch>", thread_id: 42}

      assert Mention.route(row, [lead: "hronir-machine", staffed_window: "t42"], @roster) ==
               [{"t42", "[tlon thread #42] reviewer-machine: @hronir-machine ESCALATE apply: <patch>"}]
    end

    test "a crew handle without a thread id does not resolve (no tid → no per-thread window)" do
      row = %{author: "hronir-machine", body: "@reviewer-machine hi", thread_id: nil}
      assert Mention.route(row, [lead: "hronir-machine"], @roster) == []
    end
  end
end
