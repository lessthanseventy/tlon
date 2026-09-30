defmodule Mix.Tasks.Server.EmbedBackfill do
  @shortdoc "Embed every fact and message that has no vector yet"
  @moduledoc """
  #{@shortdoc}.

  Walks every fact, then every message, whose `embedding` is still NULL and embeds it via the
  configured ollama model (`Server.Recall.embed_fact/1`, `embed_message/1`), so semantic recall and
  semantic history search can rank it. A row is left NULL when it was written before embed-on-write
  existed or while the embedder was down (`embed_on_write/1` is best-effort, never a write-path
  failure) — its search falls back to keyword until this runs. Idempotent: an embedded row is
  skipped, so a re-run only picks up what was missed. Hits the live DB and live ollama; a row the
  embedder still can't reach stays NULL and is counted, never fatal.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  import Ecto.Query

  alias Server.Fact
  alias Server.Message
  alias Server.Recall
  alias Server.Repo

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    failed = backfill(Fact, "fact", &Recall.embed_fact/1) + backfill(Message, "message", &Recall.embed_message/1)
    if failed > 0, do: exit({:shutdown, 1})
  end

  defp backfill(schema, label, embed) do
    ids = Repo.all(from r in schema, where: is_nil(r.embedding), select: r.id, order_by: [asc: r.id])
    total = length(ids)
    Mix.shell().info("embed backfill: #{total} #{label}(s) with no vector")

    {ok, failed} =
      ids
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {id, n}, {ok, failed} ->
        schema
        |> Repo.get(id)
        |> embed.()
        |> case do
          {:ok, _} ->
            {ok + 1, failed}

          {:error, reason} ->
            Mix.shell().info("  #{label} ##{id} (#{n}/#{total}) skipped: #{inspect(reason)}")
            {ok, failed + 1}
        end
      end)

    Mix.shell().info("embed backfill: #{ok} #{label}(s) embedded, #{failed} left NULL")
    failed
  end
end
