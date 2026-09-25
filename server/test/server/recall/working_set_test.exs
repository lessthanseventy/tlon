defmodule Server.Recall.WorkingSetTest do
  # The DB-backed gatherer: real thread facts → strength-ranked, budgeted working set
  # (design: docs/plans/2026-08-19-funes-forgetting-design.md). Reads back through SQLite.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Recall

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "recall thread"})
    %{thread: thread}
  end

  defp ids(ws), do: Enum.map(ws, & &1.id)

  test "a thread's working set carries what its PROJECT learned on other threads, and no other project's" do
    {:ok, ws} = Server.Workspaces.register(%{name: "scoped"})
    {:ok, tlon} = Server.Projects.register(%{workspace_id: ws.id, name: "tlon", repos: []})
    {:ok, machine} = Server.Projects.register(%{workspace_id: ws.id, name: "machine", repos: []})
    {:ok, earlier} = Channel.open_thread(%{title: "earlier", workspace_id: ws.id, project_id: tlon.id})
    {:ok, now} = Channel.open_thread(%{title: "now", workspace_id: ws.id, project_id: tlon.id})
    {:ok, elsewhere} = Channel.open_thread(%{title: "elsewhere", workspace_id: ws.id, project_id: machine.id})

    {:ok, fact} =
      Dossier.bank_fact(%{thread_id: earlier.id, kind: "learned", text: "menard edits Elixir", provenance: "derived"})

    assert fact.id in ids(Recall.working_set_for_thread(now, budget: 10_000))
    refute fact.id in ids(Recall.working_set_for_thread(elsewhere, budget: 10_000))
    # the LEARNINGS pane stays the thread's own
    refute fact.id in Enum.map(Recall.thread_learnings(now).shown, & &1.id)
  end

  describe "coverage/0 — the Memory-pane observability read" do
    test "counts facts, embeddings, and the floor against the budget", %{thread: thread} do
      {:ok, msg} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "always use mise"})
      {:ok, con} = Dossier.bank_stated_fact(msg, %{kind: "constraint"})
      {:ok, _note} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "a note", provenance: "derived"})

      # Embed one fact so coverage reflects partial semantic coverage.
      Recall.store_embedding(con, [1.0, 0.0, 0.0], "test-model")

      cov = Recall.coverage()
      assert cov.facts == 2
      assert cov.embedded == 1
      assert cov.pinned_count == 1
      assert cov.pinned_tokens > 0
      assert cov.budget > 0
      assert is_binary(cov.model)
    end
  end

  test "a rechecked fact outranks an unchecked one of equal age", %{thread: thread} do
    {:ok, plain} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "plain observation", provenance: "derived"})

    {:ok, proven} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "proven observation", provenance: "derived"})

    {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "check_passed", correlation: "fact:#{proven.id}"})

    ids = ids(Recall.working_set_for_thread(thread, budget: 10_000))
    assert Enum.find_index(ids, &(&1 == proven.id)) < Enum.find_index(ids, &(&1 == plain.id))
  end

  test "operator-stated constraints are pinned first, ahead of derived facts", %{thread: thread} do
    {:ok, msg} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "always use mise for elixir"})
    {:ok, con} = Dossier.bank_stated_fact(msg, %{kind: "constraint"})

    {:ok, note} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "a derived note", provenance: "derived"})

    ids = ids(Recall.working_set_for_thread(thread, budget: 10_000))
    assert hd(ids) == con.id
    assert note.id in ids
  end

  test "the token budget drops the weaker fact", %{thread: thread} do
    big = String.duplicate("x ", 60)
    {:ok, weak} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: big, provenance: "derived"})
    {:ok, strong} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: big, provenance: "derived"})
    {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "check_passed", correlation: "fact:#{strong.id}"})

    tokens = max(div(String.length(big), 4), 1)
    ids = ids(Recall.working_set_for_thread(thread, budget: tokens + 2))
    assert strong.id in ids
    refute weak.id in ids
  end

  test "with a query, the semantically closer fact outranks a distant one", %{thread: thread} do
    {:ok, near} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "credential login flow", provenance: "derived"})

    {:ok, far} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "bright autumn leaves", provenance: "derived"})

    {:ok, _} = Recall.store_embedding(near, [0.9, 0.1], "test")
    {:ok, _} = Recall.store_embedding(far, [0.0, 1.0], "test")

    # query vector points at `near`; `far` is orthogonal (cosine 0)
    ids = ids(Recall.working_set_for_thread(thread, budget: 10_000, query_embedding: [1.0, 0.0]))
    assert Enum.find_index(ids, &(&1 == near.id)) < Enum.find_index(ids, &(&1 == far.id))
  end

  test "a cited touch lifts a fact above an equal unreferenced one", %{thread: thread} do
    {:ok, plain} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "plain", provenance: "derived"})
    {:ok, used} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "used", provenance: "derived"})
    {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "cited", correlation: "fact:#{used.id}"})

    ids = ids(Recall.working_set_for_thread(thread, budget: 10_000))
    assert Enum.find_index(ids, &(&1 == used.id)) < Enum.find_index(ids, &(&1 == plain.id))
  end

  test "a keyword query surfaces an un-embedded matching fact via FTS", %{thread: thread} do
    {:ok, match} =
      Dossier.bank_fact(%{
        thread_id: thread.id,
        kind: "learned",
        text: "the credential rotation policy",
        provenance: "derived"
      })

    {:ok, other} =
      Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "unrelated banana notes", provenance: "derived"})

    # query_embedding: [] stubs the semantic term offline (no ollama); the FTS keyword half drives.
    ids = ids(Recall.working_set_for_thread(thread, budget: 10_000, query: "credential", query_embedding: []))
    assert Enum.find_index(ids, &(&1 == match.id)) < Enum.find_index(ids, &(&1 == other.id))
  end
end
