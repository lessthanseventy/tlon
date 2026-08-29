defmodule Server.QuestionTest do
  # Knowing what you don't know is first-class (pi doc §5 slice 4): questions are task
  # knowledge-gaps scoped to a thread, open until resolved. The reads are load-bearing —
  # UNKNOWNS capped+counted, resolved excluded — so they get the tests. Shared DB, no
  # sandbox; every assertion reads back through SQLite.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Question
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "embed raxol?"})
    %{thread: thread}
  end

  describe "raise_question/1 and resolve_question/2" do
    test "raise opens an open question (resolved_at nil) that reads back", %{thread: thread} do
      assert {:ok, q} = Dossier.raise_question(%{thread_id: thread.id, text: "does raxol support embedding?"})
      assert q.text == "does raxol support embedding?"
      assert q.state == "open"
      assert is_nil(q.resolved_at)

      row = Repo.get(Question, q.id)
      assert row.thread_id == thread.id
      assert row.state == "open"
    end

    test "raise requires text and thread_id", %{thread: thread} do
      assert {:error, _} = Dossier.raise_question(%{thread_id: thread.id})
      assert {:error, _} = Dossier.raise_question(%{text: "no thread"})
    end

    test "resolve sets state, stamps resolved_at (idempotent), records the answer", %{thread: thread} do
      {:ok, q} = Dossier.raise_question(%{thread_id: thread.id, text: "which pane lib?"})
      assert {:ok, resolved} = Dossier.resolve_question(q, "raxol, via ghostty_ex")
      assert resolved.state == "resolved"
      assert resolved.resolution == "raxol, via ghostty_ex"
      assert resolved.resolved_at

      first_stamp = resolved.resolved_at
      {:ok, again} = Dossier.resolve_question(Repo.get(Question, q.id), "changed my mind")
      assert again.resolved_at == first_stamp
    end

    test "resolve without an answer is allowed (the gap can close unrecorded)", %{thread: thread} do
      {:ok, q} = Dossier.raise_question(%{thread_id: thread.id, text: "open q"})
      assert {:ok, resolved} = Dossier.resolve_question(q)
      assert resolved.state == "resolved"
      assert is_nil(resolved.resolution)
    end
  end

  describe "open_questions_for_thread/1 — UNKNOWNS, capped + counted" do
    test "open questions newest-first, cut at five with a count, resolved excluded", %{thread: thread} do
      qs = for i <- 1..7, do: elem(Dossier.raise_question(%{thread_id: thread.id, text: "q #{i}"}), 1)
      Dossier.resolve_question(Enum.at(qs, 0), "answered")

      %{shown: shown, more: more} = Dossier.open_questions_for_thread(thread)
      assert length(shown) == 5
      assert more == 1
      refute Enum.any?(shown, &(&1.text == "q 1"))
    end

    test "only this thread's open questions (thread-scoped)", %{thread: thread} do
      {:ok, other} = Channel.open_thread(%{title: "other"})
      Dossier.raise_question(%{thread_id: other.id, text: "elsewhere"})
      Dossier.raise_question(%{thread_id: thread.id, text: "here"})

      %{shown: shown, more: more} = Dossier.open_questions_for_thread(thread)
      assert Enum.map(shown, & &1.text) == ["here"]
      assert more == 0
    end
  end
end
