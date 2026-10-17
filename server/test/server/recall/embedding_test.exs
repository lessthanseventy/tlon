defmodule Server.Recall.EmbeddingTest do
  # Semantic relevance's pure seam: cosine similarity between fact vectors (design:
  # docs/plans/2026-08-19-funes-forgetting-design.md). The ollama embed/1 call itself is
  # smoke-tested live, not here — the suite stays headless and offline.
  use ExUnit.Case, async: true

  alias Server.Recall.Embedding

  test "a query the embedder can't embed is nil, and says why in the log" do
    log = ExUnit.CaptureLog.capture_log(fn -> assert Server.Recall.embed_query("anything") == nil end)
    assert log =~ "[warning]"
    assert log =~ "recall: the query embedding failed, relevance is keyword-only:"
  end

  test "identical vectors have cosine 1.0" do
    assert_in_delta Embedding.cosine([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), 1.0, 0.0001
  end

  test "orthogonal vectors have cosine 0.0" do
    assert_in_delta Embedding.cosine([1.0, 0.0], [0.0, 1.0]), 0.0, 0.0001
  end

  test "opposite vectors have cosine -1.0" do
    assert_in_delta Embedding.cosine([1.0, 1.0], [-1.0, -1.0]), -1.0, 0.0001
  end

  test "a zero vector is safely uncorrelated (no divide-by-zero)" do
    assert Embedding.cosine([0.0, 0.0], [1.0, 2.0]) == 0.0
  end
end
