defmodule Server.Recall.EmbeddingStoreTest do
  # The embedding STORAGE seam (design: docs/plans/2026-08-19-funes-forgetting-design.md): a fact
  # carries a vector + the model that made it, written after bank_fact. Offline — a vector is
  # injected, so the suite never calls ollama (embed_fact/1 is smoke-tested live, not here).
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Fact
  alias Server.Recall
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "embed thread"})
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "x", provenance: "derived"})
    %{fact: fact}
  end

  test "a fact's embedding vector + model store and read back through SQLite", %{fact: fact} do
    assert is_nil(Repo.get(Fact, fact.id).embedding)

    {:ok, _} = Recall.store_embedding(fact, [0.1, 0.2, 0.3], "nomic-embed-text")

    reloaded = Repo.get(Fact, fact.id)
    assert reloaded.embedding == [0.1, 0.2, 0.3]
    assert reloaded.embedding_model == "nomic-embed-text"
  end
end
