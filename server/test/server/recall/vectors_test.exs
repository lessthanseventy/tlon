defmodule Server.Recall.VectorsTest do
  # Recall scores up to 500 facts per brief, twice: decoding each vector's JSON and a list cosine
  # cost ~1.3 s per 500 on the live corpus (B4). The cache holds each fact's unit vector packed.
  use ExUnit.Case, async: false

  alias Server.Recall
  alias Server.Recall.Embedding
  alias Server.Recall.Vectors

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Server.Channel.open_thread(%{title: "vectors"})

    bank = fn text ->
      Server.Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: "derived"})
    end

    {:ok, a} = bank.("the service listens on port 4041")
    {:ok, b} = bank.("the release pointer is refs/heads/live")
    {:ok, a} = Recall.store_embedding(a, [0.3, -0.4, 1.2], "m")
    {:ok, _} = Recall.store_embedding(b, [0.0, 0.0, 0.0], "m")
    %{a: a, b: b}
  end

  test "the dot of two packed vectors is their cosine" do
    x = [0.3, -0.4, 1.2]
    y = [1.0, 2.0, -0.5]
    assert_in_delta Vectors.dot(Vectors.pack(x), Vectors.pack(y)), Embedding.cosine(x, y), 1.0e-12
    assert Vectors.dot(Vectors.pack([0.0, 0.0]), Vectors.pack([1.0, 2.0])) == 0.0
  end

  test "a fact's vector is read from the db once, then from the cache; a new embedding replaces it", %{a: a, b: b} do
    first = Vectors.for_ids([a.id, b.id, -1])
    assert first |> Map.keys() |> Enum.sort() == Enum.sort([a.id, b.id])

    assert queries(fn -> assert Vectors.for_ids([a.id, b.id]) == first end) == 0

    {:ok, _} = Recall.store_embedding(a, [1.0, 0.0, 0.0], "m")
    assert_in_delta Vectors.dot(Vectors.for_ids([a.id])[a.id], Vectors.pack([1.0, 0.0, 0.0])), 1.0, 1.0e-12
  end

  defp queries(fun) do
    test = self()
    id = "vectors-queries-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:server, :repo, :query], fn _, _, _, _ -> if self() == test, do: send(test, :query) end, nil)
    fun.()
    :telemetry.detach(id)
    count(0)
  end

  defp count(n) do
    receive do
      :query -> count(n + 1)
    after
      0 -> n
    end
  end
end
