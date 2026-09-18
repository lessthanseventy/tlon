defmodule Server.References do
  @moduledoc """
  Cross-thread references in message bodies (Amp's `@thread-id`, field survey §4 adopt #5): a
  `#42` in a post cites thread 42, and the brief resolves the citation to the thread's title and
  lead, so the record composes instead of sitting as inert history. Pure over the text; the
  lookup is one query for all ids in a message tail.
  """
  import Ecto.Query

  alias Server.Repo
  alias Server.Thread

  # `#42` not glued to a word or another `#` (a URL fragment, `##heading`); ids are 1..7 digits.
  @ref ~r/(?<![\p{L}\p{N}_#\/])#(\d{1,7})(?!\d)/u

  @doc "The thread ids a body cites, in order, deduplicated."
  def thread_ids(nil), do: []

  def thread_ids(body) when is_binary(body) do
    @ref |> Regex.scan(body) |> Enum.map(fn [_, id] -> String.to_integer(id) end) |> Enum.uniq()
  end

  @doc """
  Resolve the threads cited across `messages` (anything with a `body`): `[%{id, title, stage,
  lead}]` for the ids that exist, cited order, unknown ids dropped. Excludes `self_id` (a thread
  naming itself is not a citation).
  """
  def cited(messages, self_id \\ nil) do
    ids =
      messages
      |> Enum.flat_map(&thread_ids(Map.get(&1, :body)))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == self_id))

    if ids == [] do
      []
    else
      rows =
        from(t in Thread,
          left_join: a in Server.Agent,
          on: a.id == t.agent_id,
          where: t.id in ^ids,
          select: {t.id, %{id: t.id, title: t.title, stage: t.stage, lead: a.name}}
        )
        |> Repo.all()
        |> Map.new()

      ids |> Enum.map(&Map.get(rows, &1)) |> Enum.reject(&is_nil/1)
    end
  end
end
