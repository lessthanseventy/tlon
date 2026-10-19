defmodule Server.Diary do
  @moduledoc """
  What each seat did, read from real rows (souls design §4, step 5). A builder (credited only when
  its archetype is `builder`): a workline it posted on that landed (`shipped`), and a send-back of a
  thread it posted on (`bounced`, with `by`, the seat that sent it back, when one did — never
  credited with it). Any seat on the bench, for what it explicitly did: a QA verdict (`qa`,
  `verdict` pass|fail), a review (`reviewed`, `verdict` approve|request_changes) and a librarian's
  supersede or forget (`curated`, `action`, the reason in `title`). Read only; the weekly job turns
  it into diary lines.
  """
  import Ecto.Query

  alias Server.{Event, Message, Repo, Soul, Thread}

  @type entry :: %{
          required(:kind) => :shipped | :bounced | :qa | :reviewed | :curated,
          required(:thread_id) => integer(),
          required(:title) => String.t(),
          required(:at) => DateTime.t(),
          optional(:by) => String.t() | nil,
          optional(:verdict) => String.t(),
          optional(:action) => String.t()
        }

  @doc "Per seat, its entries since `since`, oldest first. `%{}` when nothing happened."
  @spec history(integer(), DateTime.t()) :: %{String.t() => [entry()]}
  def history(workspace_id, %DateTime{} = since) do
    seats = seats(workspace_id)
    landed = landed(workspace_id, since)
    bounced = bounced(workspace_id, since)
    authors = authors(Enum.map(landed ++ bounced, & &1.thread_id))

    built =
      for {kind, row} <- Enum.map(landed, &{:shipped, &1}) ++ Enum.map(bounced, &{:bounced, &1}),
          seat <- Map.get(authors, row.thread_id, []),
          seats[seat] == "builder",
          seat != row[:by],
          do: {seat, row |> Map.take([:thread_id, :title, :at, :by]) |> Map.put(:kind, kind)}

    acted =
      for {seat, entry} <- verdicts(workspace_id, since) ++ curation(workspace_id, since),
          Map.has_key?(seats, seat),
          do: {seat, entry}

    (built ++ acted)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {seat, entries} -> {seat, Enum.sort_by(entries, & &1.at, DateTime)} end)
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
    case written_through(seat) do
      nil -> true
      written -> Date.diff(today, written) >= @spacing
    end
  end

  @doc "Drop the entries on or before the date of the seat's newest diary line: already written."
  @spec unwritten(String.t(), [entry()]) :: [entry()]
  def unwritten(seat, items) do
    case written_through(seat) do
      nil -> items
      written -> Enum.reject(items, &(Date.compare(DateTime.to_date(&1.at), written) != :gt))
    end
  end

  defp written_through(seat) do
    with line when is_binary(line) <- seat |> Soul.diary() |> List.last(),
         [_, date] <- Regex.run(~r/^- (\d{4}-\d{2}-\d{2}):/, line),
         {:ok, written} <- Date.from_iso8601(date) do
      written
    else
      _ -> nil
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
  defp describe(%{kind: :bounced, title: t, by: by}) when is_binary(by), do: ~s(- sent back by #{by} on "#{t}")
  defp describe(%{kind: :bounced, title: t}), do: ~s(- sent back on "#{t}")
  defp describe(%{kind: :qa, title: t, verdict: v}), do: ~s(- gave QA a #{v} on "#{t}")
  defp describe(%{kind: :reviewed, title: t, verdict: v}), do: ~s(- reviewed "#{t}": #{v})
  defp describe(%{kind: :curated, action: a, title: why}), do: ~s(- #{a} a fact: #{why})

  defp fallback(%{kind: :shipped, title: t}), do: ~s(shipped "#{t}".)
  defp fallback(%{kind: :bounced, title: t, by: by}) when is_binary(by), do: ~s(sent back by #{by} on "#{t}".)
  defp fallback(%{kind: :bounced, title: t}), do: ~s(sent back on "#{t}".)
  defp fallback(%{kind: :qa, title: t, verdict: v}), do: ~s(gave QA a #{v} on "#{t}".)
  defp fallback(%{kind: :reviewed, title: t, verdict: v}), do: ~s(reviewed "#{t}": #{v}.)
  defp fallback(%{kind: :curated, action: a, title: why}), do: ~s(#{a} a fact: #{why}.)

  defp seats(workspace_id) do
    workspace_id
    |> Server.Workspaces.bench_all()
    |> Map.new(&{&1.name, &1.archetype})
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
    from(e in Event,
      join: t in Thread,
      on: t.id == e.thread_id,
      where: t.workspace_id == ^workspace_id and e.kind == "stage_advanced" and e.created_at >= ^since,
      select: %{thread_id: t.id, title: t.title, at: e.created_at, detail: e.detail}
    )
    |> Repo.all()
    |> Enum.filter(&Map.has_key?(&1.detail || %{}, "bounced"))
    |> Enum.map(&(&1 |> Map.put(:by, &1.detail["by"]) |> Map.delete(:detail)))
  end

  defp authors(thread_ids) do
    from(m in Message,
      where: m.thread_id in ^thread_ids and not is_nil(m.author),
      distinct: true,
      select: {m.thread_id, m.author}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp verdicts(workspace_id, since) do
    from(e in Event,
      join: t in Thread,
      on: t.id == e.thread_id,
      where:
        t.workspace_id == ^workspace_id and e.kind in ["check_passed", "check_failed"] and e.created_at >= ^since and
          (like(e.correlation, "workline:%:qa") or like(e.correlation, "workline:%:review")),
      order_by: e.id,
      select: %{thread_id: t.id, title: t.title, at: e.created_at, correlation: e.correlation, detail: e.detail}
    )
    |> Repo.all()
    |> Enum.flat_map(&verdict/1)
  end

  # `Server.Workline.qa_verdict/5` and `review_verdict/4` record the actor in the check's `cmd`
  defp verdict(%{correlation: correlation, detail: detail} = row) do
    entry = Map.take(row, [:thread_id, :title, :at])

    case {String.ends_with?(correlation, ":qa"), detail["cmd"]} do
      {true, "qa by " <> seat} ->
        [{seat, Map.merge(entry, %{kind: :qa, verdict: if(detail["exit"] == 0, do: "pass", else: "fail")})}]

      {false, "review verdict by " <> seat} ->
        [{seat, Map.merge(entry, %{kind: :reviewed, verdict: detail["tail"]})}]

      _ ->
        []
    end
  end

  # a librarian's `superseded`/`forgotten` events (`Server.Librarian`), `by` in the detail; the
  # reason stands in for the title, as most are not on a thread
  defp curation(workspace_id, since) do
    from(e in Event,
      left_join: t in Thread,
      on: t.id == e.thread_id,
      where:
        e.kind in ["superseded", "forgotten"] and like(e.correlation, "fact:%") and e.created_at >= ^since and
          (is_nil(e.thread_id) or t.workspace_id == ^workspace_id),
      order_by: e.id,
      select: %{thread_id: e.thread_id, at: e.created_at, action: e.kind, detail: e.detail}
    )
    |> Repo.all()
    |> Enum.flat_map(fn
      %{detail: %{"by" => seat} = detail} = row when is_binary(seat) ->
        [
          {seat,
           %{kind: :curated, action: row.action, thread_id: row.thread_id, title: detail["reason"] || "", at: row.at}}
        ]

      _ ->
        []
    end)
  end
end
