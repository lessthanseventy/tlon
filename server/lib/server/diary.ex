defmodule Server.Diary do
  @moduledoc """
  What each builder seat did, read from real rows (souls design §4, step 5): a workline it posted
  on that landed (`shipped`), and a send-back of a thread it posted on (`bounced`). Read only; the
  weekly job turns it into diary lines. A seat is credited only when its archetype is `builder`.
  """
  import Ecto.Query

  alias Server.{Event, Message, Repo, Thread}

  @type entry :: %{kind: :shipped | :bounced, thread_id: integer(), title: String.t(), at: DateTime.t()}

  @doc "Per builder seat, its entries since `since`, oldest first. `%{}` when nothing happened."
  @spec history(integer(), DateTime.t()) :: %{String.t() => [entry()]}
  def history(workspace_id, %DateTime{} = since) do
    builders = builders(workspace_id)
    landed = landed(workspace_id, since)
    bounced = bounced(workspace_id, since)

    authors = authors(Enum.map(landed ++ bounced, & &1.thread_id))

    grouped =
      for {kind, row} <- Enum.map(landed, &{:shipped, &1}) ++ Enum.map(bounced, &{:bounced, &1}),
          seat <- Map.get(authors, row.thread_id, []),
          MapSet.member?(builders, seat),
          reduce: %{} do
        acc ->
          entry = %{kind: kind, thread_id: row.thread_id, title: row.title, at: row.at}
          Map.update(acc, seat, [entry], &(&1 ++ [entry]))
      end

    Map.new(grouped, fn {seat, entries} -> {seat, Enum.sort_by(entries, & &1.at, DateTime)} end)
  end

  defp builders(workspace_id) do
    workspace_id
    |> Server.Workspaces.bench_all()
    |> Enum.filter(&(&1.archetype == "builder"))
    |> MapSet.new(& &1.name)
  end

  defp landed(workspace_id, since) do
    Repo.all(
      from e in Event,
        join: t in Thread,
        on: t.id == e.thread_id,
        where:
          t.workspace_id == ^workspace_id and e.kind == "work_landed" and
            like(e.correlation, "workline:%:landing") and e.created_at >= ^since,
        select: %{thread_id: t.id, title: t.title, at: e.created_at}
    )
  end

  defp bounced(workspace_id, since) do
    Repo.all(
      from e in Event,
        join: t in Thread,
        on: t.id == e.thread_id,
        where: t.workspace_id == ^workspace_id and e.kind == "stage_advanced" and e.created_at >= ^since,
        select: %{thread_id: t.id, title: t.title, at: e.created_at, detail: e.detail}
    )
    |> Enum.filter(&Map.has_key?(&1.detail || %{}, "bounced"))
    |> Enum.map(&Map.delete(&1, :detail))
  end

  defp authors(thread_ids) do
    Repo.all(
      from m in Message,
        where: m.thread_id in ^thread_ids and not is_nil(m.author),
        distinct: true,
        select: {m.thread_id, m.author}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
