defmodule Console.Orchestrator.RouterTest do
  # The pure intent-router behind the tertius command line (Slice 1): natural-language meta-intent
  # → a dispatch action. Parsing only — handle→thread and id resolution happen at dispatch. The
  # router is a pure function so the grammar is pinned without a live channel.
  use ExUnit.Case, async: true

  alias Console.Orchestrator.Router

  describe "tell — post to a coworker" do
    test "strips a leading @ and splits handle from body" do
      assert Router.route("tell @pi prioritize the delete verbs") ==
               {:post, "pi", "prioritize the delete verbs"}
    end

    test "works without the @" do
      assert Router.route("tell hronir ship it") == {:post, "hronir", "ship it"}
    end
  end

  describe "remember / note" do
    test "remember → a note" do
      assert Router.route("remember leads are managers not doers") == {:note, "leads are managers not doers"}
    end

    test "note → a note" do
      assert Router.route("note the cockpit uses tmux sessions") == {:note, "the cockpit uses tmux sessions"}
    end
  end

  describe "file a ticket" do
    test "'file a ticket ...' → a ticket" do
      assert Router.route("file a ticket auth is fucked") == {:ticket, "auth is fucked"}
    end

    test "'ticket: ...' → a ticket" do
      assert Router.route("ticket: flaky test in orbis") == {:ticket, "flaky test in orbis"}
    end
  end

  describe "open work at a stage" do
    test "spike → build stage" do
      assert Router.route("spike a redis cache") == {:open, "build", "a redis cache"}
    end

    test "explore → untracked (nil stage)" do
      assert Router.route("explore the worktree idea") == {:open, nil, "the worktree idea"}
    end

    test "build → intent stage" do
      assert Router.route("build the ticket tracker properly") == {:open, "intent", "the ticket tracker properly"}
    end
  end

  describe "approve / queries" do
    test "approve #N and approve N" do
      assert Router.route("approve #38") == {:approve, 38}
      assert Router.route("approve 38") == {:approve, 38}
    end

    test "what's blocked / who's free" do
      assert Router.route("what's blocked") == {:query, :blocked}
      assert Router.route("who's free") == {:query, :roster}
    end
  end

  describe "fallback + robustness" do
    test "an unrecognized line is chat" do
      assert Router.route("hey what do you think about this") == {:chat, "hey what do you think about this"}
    end

    test "matching is case-insensitive but preserves the body" do
      assert Router.route("TELL @pi Do The Thing") == {:post, "pi", "Do The Thing"}
    end

    test "leading/trailing whitespace is trimmed" do
      assert Router.route("  remember X  ") == {:note, "X"}
    end

    test "a bare verb with no argument falls through to chat" do
      assert Router.route("tell") == {:chat, "tell"}
      assert Router.route("remember") == {:chat, "remember"}
    end
  end
end
