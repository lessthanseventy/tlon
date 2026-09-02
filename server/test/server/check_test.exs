defmodule Server.CheckTest do
  # Measured verification (roadmap #5): record_check lands a command's REAL exit code as
  # a check_passed/check_failed event, so "it works" is measured, never self-reported. The
  # kind is keyed on the number; the reads (CHECKS) surface the current verification state.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "verify the drain"})
    %{thread: thread}
  end

  describe "record_check/1 — keyed on the real exit code" do
    test "exit 0 lands a check_passed event carrying the cmd + tail", %{thread: thread} do
      assert {:ok, event} =
               Dossier.record_check(%{
                 thread_id: thread.id,
                 cmd: "mise run check",
                 exit: 0,
                 tail: "135 tests, 0 failures"
               })

      assert event.kind == "check_passed"
      assert event.detail["cmd"] == "mise run check"
      assert event.detail["exit"] == 0
      assert event.detail["tail"] == "135 tests, 0 failures"
    end

    test "a non-zero exit lands a check_failed event", %{thread: thread} do
      assert {:ok, event} = Dossier.record_check(%{thread_id: thread.id, cmd: "mix test", exit: 1, tail: "1 failure"})
      assert event.kind == "check_failed"
      assert event.detail["exit"] == 1
    end
  end

  describe "recheck_fact/2 — re-run a fact's OWN check_cmd → a check correlated to it" do
    setup %{thread: thread} do
      {:ok, fact} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "the drain re-delivers on restart",
          provenance: "derived",
          check_cmd: "mix test test/funes/switchboard_test.exs"
        })

      %{fact: fact}
    end

    test "exit 0 lands a check_passed correlated to the fact, cmd pinned to its check_cmd", %{
      thread: thread,
      fact: fact
    } do
      assert {:ok, event} = Dossier.recheck_fact(fact, %{exit: 0, tail: "3 tests, 0 failures"})

      assert event.kind == "check_passed"
      assert event.thread_id == thread.id
      # the recorded cmd is the FACT's own check_cmd — the agent cannot substitute another
      assert event.detail["cmd"] == fact.check_cmd
      assert event.detail["exit"] == 0
      assert event.detail["tail"] == "3 tests, 0 failures"
      # correlated to the fact's lifecycle — never inferred from text (§4)
      assert event.correlation == "fact:#{fact.id}"
    end

    test "a non-zero exit lands a check_failed — the drift signal", %{fact: fact} do
      assert {:ok, event} = Dossier.recheck_fact(fact, %{exit: 1, tail: "1 failure"})
      assert event.kind == "check_failed"
      assert event.correlation == "fact:#{fact.id}"
    end

    test "a fact with NO check_cmd cannot be re-verified — refused, never faked", %{thread: thread} do
      {:ok, opinion} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "an unverifiable hunch",
          provenance: "derived"
        })

      assert {:error, :no_check_cmd} = Dossier.recheck_fact(opinion, %{exit: 0, tail: ""})
    end

    test "a re-verification flows into the thread's CHECKS pane automatically", %{
      thread: thread,
      fact: fact
    } do
      {:ok, _} = Dossier.recheck_fact(fact, %{exit: 0, tail: ""})

      %{shown: shown} = Dossier.recent_checks_for_thread(thread)
      assert Enum.any?(shown, &(&1.correlation == "fact:#{fact.id}"))
    end
  end

  describe "recent_checks_for_thread/1 — CHECKS, newest first, capped + counted" do
    test "shows recent checks newest-first, cut at five with a count, thread-scoped", %{thread: thread} do
      {:ok, other} = Channel.open_thread(%{title: "other"})
      Dossier.record_check(%{thread_id: other.id, cmd: "elsewhere", exit: 0, tail: ""})

      for i <- 1..6, do: Dossier.record_check(%{thread_id: thread.id, cmd: "check #{i}", exit: rem(i, 2), tail: ""})

      %{shown: shown, more: more} = Dossier.recent_checks_for_thread(thread)
      assert length(shown) == 5
      assert more == 1
      # newest first: the last recorded (check 6, exit 0 → passed) heads the list
      assert hd(shown).detail["cmd"] == "check 6"
      assert Enum.all?(shown, &(&1.kind in ["check_passed", "check_failed"]))
      # the other thread's check is excluded
      refute Enum.any?(shown, &(&1.detail["cmd"] == "elsewhere"))
    end
  end
end
