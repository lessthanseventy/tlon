defmodule Server.Recall.Vectors do
  @moduledoc """
  Recall's fact vectors, decoded once: each fact's embedding as a unit vector packed in a binary of
  native 64-bit floats, held in ETS. Recall scores up to `@meaning_pool` facts per brief, twice;
  decoding each vector's JSON and a list cosine cost ~1.3 s per 500 facts on the live corpus, the
  packed dot product a small part of that. A fact's vector changes only through
  `Server.Recall.store_embedding/3`, which calls `forget/1`.
  """
  import Ecto.Query

  alias Server.Fact
  alias Server.Repo

  @doc false
  def init, do: :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])

  @doc "`%{id => packed}` for the facts of `ids` that have an embedding: cached, the misses read in one query."
  def for_ids(ids) do
    {hits, misses} =
      Enum.reduce(Enum.uniq(ids), {%{}, []}, fn id, {hits, misses} ->
        case :ets.lookup(__MODULE__, id) do
          [{^id, packed}] -> {Map.put(hits, id, packed), misses}
          [] -> {hits, [id | misses]}
        end
      end)

    loaded =
      if misses == [],
        do: [],
        else: Repo.all(from f in Fact, where: f.id in ^misses and not is_nil(f.embedding), select: {f.id, f.embedding})

    packed = for {id, vector} <- loaded, do: {id, pack(vector)}
    :ets.insert(__MODULE__, packed)
    Map.merge(hits, Map.new(packed))
  end

  @doc "Drop `id`'s cached vector, so the next read takes the stored one."
  def forget(id), do: :ets.delete(__MODULE__, id)

  @doc "`vector` scaled to unit length and packed; a zero vector packs as zeros (it scores 0 against anything)."
  def pack(vector) do
    norm = :math.sqrt(Enum.reduce(vector, 0.0, &(&1 * &1 + &2)))
    scale = if norm == 0.0, do: 0.0, else: 1.0 / norm
    for x <- vector, into: <<>>, do: <<x * scale::float-64-native>>
  end

  @doc "The dot product of two packed vectors: their cosine, as both are unit length."
  def dot(a, b), do: dot(a, b, 0.0)

  defp dot(<<x::float-64-native, a::binary>>, <<y::float-64-native, b::binary>>, acc), do: dot(a, b, acc + x * y)
  defp dot(_, _, acc), do: acc
end
