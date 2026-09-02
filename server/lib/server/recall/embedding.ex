defmodule Server.Recall.Embedding do
  @moduledoc """
  Semantic relevance for the forgetting engine (design:
  `docs/plans/2026-08-19-funes-forgetting-design.md`): embed fact text with a local ollama model
  and compare by cosine. `cosine/2` is pure; `embed/1` calls ollama over Erlang's built-in
  `:httpc` (no new dep) and degrades to `{:error, _}` if the embedder is down — the recall layer
  then falls back to keyword relevance rather than failing. Endpoint/model are configurable
  (`config :server, :embedding`).
  """
  @default_endpoint "http://127.0.0.1:11434/api/embed"
  @default_model "nomic-embed-text"

  @doc "Cosine similarity of two equal-length vectors. A zero vector is uncorrelated (0.0)."
  @spec cosine([number()], [number()]) :: float()
  def cosine(a, b) do
    {dot, na, nb} =
      a
      |> Enum.zip(b)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y}, {dot, na, nb} ->
        {dot + x * y, na + x * x, nb + y * y}
      end)

    denom = :math.sqrt(na) * :math.sqrt(nb)
    if denom == 0.0, do: 0.0, else: dot / denom
  end

  @doc "Embed `text` via ollama. `{:ok, vector}` or `{:error, reason}` (never raises upward)."
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    cfg = Application.get_env(:server, :embedding, [])
    endpoint = opts[:endpoint] || cfg[:endpoint] || @default_endpoint
    model = opts[:model] || cfg[:model] || @default_model

    _ = Application.ensure_all_started(:inets)
    body = JSON.encode!(%{model: model, input: text})
    request = {String.to_charlist(endpoint), [], ~c"application/json", body}

    case :httpc.request(:post, request, [{:timeout, 10_000}], body_format: :binary) do
      {:ok, {{_v, 200, _r}, _headers, resp}} -> parse(resp)
      {:ok, {{_v, code, _r}, _headers, _resp}} -> {:error, {:http, code}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  # ollama returns %{"embeddings" => [[..vector..]]} for a single input.
  defp parse(resp) do
    case JSON.decode(resp) do
      {:ok, %{"embeddings" => [vector | _]}} when is_list(vector) -> {:ok, vector}
      {:ok, other} -> {:error, {:unexpected, other}}
      {:error, reason} -> {:error, reason}
    end
  end
end
