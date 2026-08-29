defmodule Mix.Tasks.Server.EmbedBackfill do
  @shortdoc "Embed existing facts that have no vector yet (the forgetting-engine one-off backfill)"
  @moduledoc """
  #{@shortdoc}.

  Walks every fact whose `embedding` is still NULL and embeds it via the configured ollama model
  (`Server.Recall.embed_fact/1`), so the recall read path has semantic vectors to rank by. Run this
  ONCE after enabling embed-on-write, before flipping `TLON_RECALL=1`. Idempotent — an already
  embedded fact is skipped, so a re-run only picks up what a down embedder missed. Hits the live DB
  and live ollama; a fact the embedder can't reach is left NULL (recall falls back to keyword) and
  counted, never fatal.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  import Ecto.Query

  alias Server.Fact
  alias Server.Recall
  alias Server.Repo

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    ids = Repo.all(from f in Fact, where: is_nil(f.embedding), select: f.id, order_by: [asc: f.id])
    total = length(ids)
    Mix.shell().info("embed backfill: #{total} fact(s) with no vector")

    {ok, failed} =
      ids
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {id, n}, {ok, failed} ->
        case Fact |> Repo.get(id) |> Recall.embed_fact() do
          {:ok, _} ->
            {ok + 1, failed}

          {:error, reason} ->
            Mix.shell().info("  ##{id} (#{n}/#{total}) skipped: #{inspect(reason)}")
            {ok, failed + 1}
        end
      end)

    Mix.shell().info("embed backfill: #{ok} embedded, #{failed} left NULL")
    if failed > 0, do: exit({:shutdown, 1})
  end
end
