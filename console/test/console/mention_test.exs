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
  # handle is "hronir" (post-C2.3 rename), NOT the legacy "claude".
  @roster [
    %Server.Coworker{archetype: "surveyor", name: "tertius"},
    %Server.Coworker{archetype: "builder", name: "hronir"}
  ]

  test "the handle -> window map is derived from the roster, not a compile-time table" do
    assert Mention.mentions("@hronir ping", @roster) == [{"hronir", "hronir"}]
  end

  test "an @-handle maps to its coworker window" do
    assert Mention.mentions("@hronir check MCP", @roster) == [{"hronir", "hronir"}]
    assert Mention.mentions("hey @tertius", @roster) == [{"tertius", "tertius"}]
  end

  test "a non-coworker @-handle is ignored (slack-style noise, not a route)" do
    assert Mention.mentions("@andrew nope", @roster) == []
    assert Mention.mentions("@pi gone", @roster) == []
  end

  test "an empty roster resolves nothing (funes-down degrades to no wakes)" do
    assert Mention.mentions("@hronir ping", []) == []
  end

  test "multiple mentions dedupe and keep first-seen order" do
    assert Mention.mentions("@hronir @tertius @hronir", @roster) ==
             [{"hronir", "hronir"}, {"tertius", "tertius"}]
  end

  test "route wakes every mentioned coworker EXCEPT the author's own window (loop guard)" do
    assert Mention.route(%{author: "tertius", body: "@hronir check MCP", thread_id: 1}, [], @roster) ==
             [{"hronir", "[tlon thread #1] tertius: @hronir check MCP"}]

    assert Mention.route(%{author: "hronir", body: "@tertius your turn", thread_id: 1}, [], @roster) ==
             [{"tertius", "[tlon thread #1] hronir: @tertius your turn"}]
  end

  test "the operator (not a coworker) mentioning the builder wakes it" do
    assert Mention.route(%{author: "andrew", body: "@hronir do the thing", thread_id: 7}, [], @roster) ==
             [{"hronir", "[tlon thread #7] andrew: @hronir do the thing"}]
  end

  test "a multiline body is flattened to one line (tmux send-keys is line-based)" do
    routed = Mention.route(%{author: "andrew", body: "@hronir line one\nline two", thread_id: 1}, [], @roster)
    assert [{_window, text}] = routed
    assert text == "[tlon thread #1] andrew: @hronir line one line two"
  end

  test "a message with no mention routes nowhere" do
    assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 1}, [], @roster) == []
  end

  test "a message missing thread_id still routes (with '?' for the id)" do
    assert Mention.route(%{author: "andrew", body: "@hronir hi", thread_id: nil}, [], @roster) ==
             [{"hronir", "[tlon thread ?] andrew: @hronir hi"}]
  end

  describe "route/3 with a thread lead (bare-reply wake)" do
    test "a bare reply (no @-mention) wakes the thread's lead coworker" do
      assert Mention.route(
               %{author: "andrew", body: "who am i talking to?", thread_id: 9},
               [lead: "hronir"],
               @roster
             ) == [{"hronir", "[tlon thread #9] andrew: who am i talking to?"}]
    end

    test "an explicit @-mention overrides the lead (directed, not the lead)" do
      assert Mention.route(
               %{author: "andrew", body: "@tertius you take this", thread_id: 9},
               [lead: "hronir"],
               @roster
             ) == [{"tertius", "[tlon thread #9] andrew: @tertius you take this"}]
    end

    test "the lead is not woken by its own post (loop guard still holds)" do
      assert Mention.route(
               %{author: "hronir", body: "thinking out loud", thread_id: 9},
               [lead: "hronir"],
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

      assert Mention.route(%{author: "andrew", body: "@hronir hi", thread_id: 7}, [], @roster) ==
               [{"hronir", "[tlon thread #7] andrew: @hronir hi"}]
    end
  end

  describe "route/3 with a staffed per-thread window (B1.4)" do
    test "a bare reply on a staffed thread wakes ITS t<id> window, not the standing coworker" do
      assert Mention.route(
               %{author: "andrew", body: "tell me a joke", thread_id: 2},
               [lead: "hronir", staffed_window: "t2"],
               @roster
             ) == [{"t2", "[tlon thread #2] andrew: tell me a joke"}]
    end

    test "an explicit @-mention of the lead on a staffed thread also lands on t<id>" do
      assert Mention.route(
               %{author: "andrew", body: "@hronir ping", thread_id: 2},
               [lead: "hronir", staffed_window: "t2"],
               @roster
             ) == [{"t2", "[tlon thread #2] andrew: @hronir ping"}]
    end

    test "the staffed lead's own post wakes nobody (loop guard survives the redirect)" do
      assert Mention.route(
               %{author: "hronir", body: "thinking out loud", thread_id: 2},
               [lead: "hronir", staffed_window: "t2"],
               @roster
             ) == []
    end

    test "a mention of a DIFFERENT coworker is not redirected (only the lead's window moves)" do
      assert Mention.route(
               %{author: "andrew", body: "@tertius you take it", thread_id: 2},
               [lead: "hronir", staffed_window: "t2"],
               @roster
             ) == [{"tertius", "[tlon thread #2] andrew: @tertius you take it"}]
    end

    test "nil staffed_window is the standing-thread path (no redirect)" do
      assert Mention.route(
               %{author: "andrew", body: "tell me a joke", thread_id: 1},
               [lead: "hronir", staffed_window: nil],
               @roster
             ) == [{"hronir", "[tlon thread #1] andrew: tell me a joke"}]
    end
  end

  describe "crew role resolution (per-thread windows)" do
    test "@reviewer on a thread routes to that thread's r<id> window" do
      row = %{author: "hronir", body: "@reviewer review the diff in HEAD~1", thread_id: 42}

      assert Mention.route(row, [lead: "hronir", staffed_window: "t42"], @roster) ==
               [{"r42", "[tlon thread #42] hronir: @reviewer review the diff in HEAD~1"}]
    end

    test "a reviewer's own post never wakes its own r<id> window (loop guard)" do
      row = %{author: "reviewer", body: "@reviewer note to self", thread_id: 42}
      assert Mention.route(row, [lead: "hronir", staffed_window: "t42"], @roster) == []
    end

    test "reviewer ESCALATE to the leader lands on the leader's staffed window" do
      row = %{author: "reviewer", body: "@hronir ESCALATE apply: <patch>", thread_id: 42}

      assert Mention.route(row, [lead: "hronir", staffed_window: "t42"], @roster) ==
               [{"t42", "[tlon thread #42] reviewer: @hronir ESCALATE apply: <patch>"}]
    end

    test "a crew handle without a thread id does not resolve (no tid → no per-thread window)" do
      row = %{author: "hronir", body: "@reviewer hi", thread_id: nil}
      assert Mention.route(row, [lead: "hronir"], @roster) == []
    end
  end
end
