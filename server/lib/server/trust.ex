defmodule Server.Trust do
  @moduledoc """
  A builder's track record, read from what the workline machine already writes (never a second
  telemetry): of the last 20 worklines they led through build that are finished, how many merged
  without ever being sent back to build. Earned autonomy rides on it: a builder with at least 8 such
  worklines landing first time at 80% or better has the operator's standing approval
  (`auto_land_risk`) raised by one on the worklines they built, never past 4 — fewer approval cards
  for work from a seat that keeps getting it right, and the card that does come says why.

  The record is per coworker; `record/2` splits it by the model on the leads line, the one the seat
  launched on when it took the build. A line from before the model was recorded is unknown: in the
  coworker's record, in no model's.
  """
  import Ecto.Query

  alias Server.Event
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @window 20
  @earned_after 8
  @earned_rate 0.8
  @ceiling 4

  @doc """
  The line the workline machine posts when `name` takes a workline's `stage`, with the model the seat
  launched on when known; the record reads both back. Brackets, not a separator: a model label holds
  parentheses and underscores but never `]`.
  """
  def leads_line(name, stage, model \\ nil)
  def leads_line(name, stage, nil), do: "→ #{name} leads (#{stage} stage)"
  def leads_line(name, stage, model), do: "→ #{name} leads (#{stage} stage) [model: #{model}]"

  @doc "The model a leads line was taken on, or nil (a line from before the model was recorded)."
  def model_of(body) do
    case Regex.run(~r/^→ \S+ leads \([a-z]+ stage\) \[model: ([^\]]+)\]/u, body) do
      [_, model] -> model
      _ -> nil
    end
  end

  @doc "`%{led, first_time}` over `name`'s last #{@window} finished builds, on every model, unknown included."
  def record(name), do: record(name, :any)

  @doc """
  `record/1` narrowed to the builds `name` took on `model` (the leads line's label). A line from before
  the model was recorded is in no model's record.
  """
  def record(name, model) do
    threads =
      Repo.all(
        from m in Message,
          join: t in Thread,
          on: t.id == m.thread_id,
          where:
            m.author == "tlon" and like(m.body, ^(leads_line(name, "build") <> "%")) and
              (t.stage == "landed" or t.state == "closed"),
          where: ^on_model(model),
          distinct: t.id,
          order_by: [desc: t.id],
          limit: @window,
          select: t
      )

    bounced = bounced(Enum.map(threads, & &1.id))
    %{led: length(threads), first_time: Enum.count(threads, &(&1.stage == "landed" and &1.id not in bounced))}
  end

  @doc "Whether `record` has earned a seat a step of the operator's standing approval."
  def earned?(%{led: led, first_time: first}), do: led >= @earned_after and first / led >= @earned_rate

  @doc "Who led `thread` through build (the last to take it) and on what model: `{name, model | nil}`, or nil."
  def builder(%Thread{id: id}) do
    from(m in Message,
      where: m.thread_id == ^id and m.author == "tlon" and like(m.body, "→ % leads (build stage)%"),
      order_by: [desc: m.id],
      limit: 1,
      select: m.body
    )
    |> Repo.one()
    |> case do
      nil -> nil
      body -> with [_, name] <- Regex.run(~r/^→ (\S+) leads \(build stage\)/u, body), do: {name, model_of(body)}
    end
  end

  @doc """
  The standing approval `max` as it stands for `thread`: one higher when its builder has earned it,
  never past #{@ceiling}. `{max, nil}` | `{raised, %{name, model, led, first_time}}`. The record is the
  coworker's across models (the operator's call); `model` says which one built this workline.
  """
  def allowance(thread, max) when is_integer(max) do
    with {name, model} when max < @ceiling <- builder(thread),
         record = record(name),
         true <- earned?(record) do
      {max + 1, Map.merge(record, %{name: name, model: model})}
    else
      _ -> {max, nil}
    end
  end

  # strpos, not LIKE: a model label's `_` would be a wildcard. The closing bracket makes it exact.
  defp on_model(:any), do: true
  defp on_model(model), do: dynamic([m], fragment("strpos(?, ?) > 0", m.body, ^"[model: #{model}]"))

  defp bounced([]), do: []

  defp bounced(ids) do
    Repo.all(
      from e in Event,
        where:
          e.thread_id in ^ids and e.kind == "stage_advanced" and
            fragment(
              "(?::jsonb ->> 'to') = 'build' and (?::jsonb ->> 'from') in ('verify', 'review')",
              e.detail,
              e.detail
            ),
        distinct: true,
        select: e.thread_id
    )
  end
end
