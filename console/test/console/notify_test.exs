defmodule Console.NotifyTest do
  @moduledoc """
  The desktop-notification decision + OSC formatting, headless. The actual tty write is the
  Cockpit's one-line edge; the eye test is a real ghostty raising a native notification.
  """
  use ExUnit.Case, async: true

  alias Console.Notify

  describe "for_event/2 — what deserves an interruption" do
    test "a raised question is a waiting-on-you" do
      assert {"tlon — question for you", "ship it?"} = Notify.for_event(:question_raised, %{text: "ship it?"})
    end

    test "a raised issue carries who found it" do
      assert {_title, "pi: tests flaky"} =
               Notify.for_event(:issue_raised, %{summary: "tests flaky", found_by: "pi"})
    end

    test "a session ending is a completion" do
      assert {_title, body} = Notify.for_event(:session_ended, %{agent: "pi", thread_id: 7})
      assert body =~ "pi"
      assert body =~ "7"
    end

    # The Bus event's :agent is an Ecto belongs_to, not a name string — unloaded on the events
    # that reach the cockpit, so the notifier must not interpolate it raw (the Tlön-entry crash).
    test "an unloaded agent association falls back instead of crashing" do
      not_loaded = %Ecto.Association.NotLoaded{
        __field__: :agent,
        __owner__: Console.NotifyTest,
        __cardinality__: :one
      }

      assert {_title, body} = Notify.for_event(:session_ended, %{agent: not_loaded, thread_id: 3})
      assert body =~ "session"
      assert body =~ "3"
    end

    test "a preloaded agent shows its name" do
      assert {_title, body} =
               Notify.for_event(:session_ended, %{agent: %{name: "pi"}, thread_id: 9})

      assert body =~ "pi"
    end

    test "repaint-only noise notifies nobody" do
      assert Notify.for_event(:fact_banked, %{}) == nil
      assert Notify.for_event(:message_posted, %{}) == nil
    end
  end

  describe "osc/2 — the escape is an injection boundary" do
    test "builds OSC 777 notify" do
      assert Notify.osc("t", "b") == "\e]777;notify;t;b\a"
    end

    test "strips control characters an agent-authored row could smuggle" do
      seq = Notify.osc("ti\etle", "bo\ady\x00")
      refute String.slice(seq, 2..-1//1) =~ "\e"
      refute String.trim_trailing(seq, "\a") =~ "\a"
    end

    test "a semicolon in the title cannot truncate into the body slot" do
      assert Notify.osc("a;b", "c") == "\e]777;notify;a,b;c\a"
    end
  end
end
