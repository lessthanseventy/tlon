defmodule Server.Diary do
  @moduledoc """
  What each builder seat did, read from real rows (souls design §4, step 5): a workline it posted
  on that landed (`shipped`), and a send-back of a thread it posted on (`bounced`). Read only; the
  weekly job turns it into diary lines. A seat is credited only when its archetype is `builder`.
  """
  import Ecto.Query

  alias Server.{Event, Message, Repo, Soul, Thread}

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

  @doc """
  Append the seat's diary lines for `items` (from `history/2`) under `## Diary`. The model writes up
  to three in-voice lines; when it is off, capped or says nothing usable, one dated line per item is
  written instead. Never creates a soul: a seat with no soul file is `{:error, :no_soul}`.
  """
  @spec write(String.t(), [entry()], Date.t()) :: :ok | {:error, term()}
  def write(name, items, today \\ Date.utc_today())
  def write(_name, [], _today), do: :ok

  def write(name, items, today) do
    lines = model_lines(name, items, today) || Enum.map(items, &"- #{today}: #{fallback(&1)}")
    Soul.append_diary(name, lines)
  end

  @spacing 6

  @doc "Whether the seat's week is due: its newest diary line is at least six days old, or it has none."
  @spec due?(String.t(), Date.t()) :: boolean()
  def due?(seat, today) do
    with line when is_binary(line) <- seat |> Soul.diary() |> List.last(),
         [_, date] <- Regex.run(~r/^- (\d{4}-\d{2}-\d{2}):/, line),
         {:ok, written} <- Date.from_iso8601(date) do
      Date.diff(today, written) >= @spacing
    else
      _ -> true
    end
  end

  defp model_lines(name, items, today) do
    case Server.Generator.run(prompt(name, items)) do
      {:ok, out} ->
        out
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "- "))
        |> Enum.take(3)
        |> case do
          [] -> nil
          lines -> Enum.map(lines, &"- #{today}: #{String.slice(String.trim_leading(&1, "- "), 0, 200)}")
        end

      _ ->
        nil
    end
  end

  defp prompt(name, items) do
    """
    You are #{name}. #{Soul.voice(name)}

    Write 1 to 3 diary lines for this week, each in your own voice, each starting with "- ". Dry,
    no markdown headings, nothing about decisions. What happened:
    #{Enum.map_join(items, "\n", &describe/1)}
    """
  end

  defp describe(%{kind: :shipped, title: t}), do: ~s(- shipped "#{t}")
  defp describe(%{kind: :bounced, title: t}), do: ~s(- sent back on "#{t}")

  defp fallback(%{kind: :shipped, title: t}), do: ~s(shipped "#{t}".)
  defp fallback(%{kind: :bounced, title: t}), do: ~s(sent back on "#{t}".)

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
