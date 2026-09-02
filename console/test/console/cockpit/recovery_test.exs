defmodule Console.Cockpit.RecoveryTest do
  use ExUnit.Case, async: true

  alias Console.Cockpit.Recovery

  describe "crash_report/1: only a real crash gets logged" do
    test "a clean quit (:normal / :shutdown) produces no report" do
      assert Recovery.crash_report(:normal) == nil
      assert Recovery.crash_report(:shutdown) == nil
      assert Recovery.crash_report({:shutdown, :quit}) == nil
    end

    test "a crash reason is formatted into a report (with the stacktrace, when present)" do
      report = Recovery.crash_report({%RuntimeError{message: "boom"}, []})
      assert is_binary(report)
      assert report =~ "boom"
    end

    test "crash_summary takes the first non-blank report line (for the filed issue's title)" do
      assert Recovery.crash_summary("\n** (RuntimeError) boom\n    at foo.ex:1\n") ==
               "** (RuntimeError) boom"
    end

    test "crash_issue_open? reads the capped %{shown, more} shape open_issues_for_thread returns" do
      issues = %{shown: [%{summary: "aleph crashed: boom"}], more: 3}
      assert Recovery.crash_issue_open?(issues, "aleph crashed: boom")
      refute Recovery.crash_issue_open?(issues, "aleph crashed: other")
      refute Recovery.crash_issue_open?(%{shown: [], more: 0}, "aleph crashed: boom")
    end
  end

  # run/0's crash-recovery decision: a clean quit ends; a crash relaunches the cockpit in place
  # (funes + the session terminals stay supervised), unless it's crash-looping.
  describe "resurrect_decision/3 — what run/0 does after the cockpit goes DOWN" do
    test "a clean quit (:normal / :shutdown) ends the session, never resurrects" do
      assert Recovery.resurrect_decision(:normal, 0, 10) == :quit
      assert Recovery.resurrect_decision(:shutdown, 2, 10) == :quit
    end

    test "a crash relaunches, counting the strike" do
      assert Recovery.resurrect_decision({:badmatch, nil}, 0, 50) == {:resurrect, 1}
      assert Recovery.resurrect_decision({:badmatch, nil}, 1, 50) == {:resurrect, 2}
    end

    test "too many rapid crashes in a row stay down instead of spinning the terminal" do
      assert Recovery.resurrect_decision({:badmatch, nil}, 2, 50) == {:stop, 3}
    end

    test "a cockpit that stayed up a while resets the strike count — an isolated crash still heals" do
      assert Recovery.resurrect_decision({:badmatch, nil}, 2, 30_000) == {:resurrect, 1}
    end

    # A relaunch into a dead :standard_io would raise on init's alt-screen writes and turn a
    # recoverable crash into "aleph failed to start" — detect it up front and stay down cleanly.
    test "a crash with dead stdio stays down instead of relaunching into a dead terminal" do
      assert Recovery.resurrect_decision({:badmatch, nil}, 0, 50, false) == :dead_io
      assert Recovery.resurrect_decision({:badmatch, nil}, 2, 30_000, false) == :dead_io
    end

    test "a clean quit with dead stdio is still just a quit" do
      assert Recovery.resurrect_decision(:normal, 0, 10, false) == :quit
    end

    test "live stdio keeps the resurrect behavior (explicit 4-arity)" do
      assert Recovery.resurrect_decision({:badmatch, nil}, 0, 50, true) == {:resurrect, 1}
    end
  end
end
