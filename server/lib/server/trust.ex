defmodule Server.Trust do
  @moduledoc """
  A builder's track record, read from what the workline machine already writes (never a second
  telemetry): of the last 20 worklines they led through build that are finished, how many merged
  without ever being sent back to build. Earned autonomy rides on it: a builder with at least 8 such
  worklines landing first time at 80% or better has the operator's standing approval
  (`auto_land_risk`) raised by one on the worklines they built, never past 4 — fewer approval cards
  for work from a seat that keeps getting it right, and the card that does come says why.
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

  @doc "The line the workline machine posts when `name` takes a workline's `stage`; the record reads it back."
  def leads_line(name, stage), do: "→ #{name} leads (#{stage} stage)"

  @doc "`%{led, first_time}` over `name`'s last #{@window} finished builds."
  def record(name) do
    threads =
      Repo.all(
        from m in Message,
          join: t in Thread,
          on: t.id == m.thread_id,
          where:
            m.author == "tlon" and like(m.body, ^(leads_line(name, "build") <> "%")) and
              (t.stage == "landed" or t.state == "closed"),
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

  @doc "Who led `thread` through build (the last to take it), or nil."
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
      body -> with [_, name] <- Regex.run(~r/^→ (\S+) leads \(build stage\)/u, body), do: name
    end
  end

  @doc """
  The standing approval `max` as it stands for `thread`: one higher when its builder has earned it,
  never past #{@ceiling}. `{max, nil}` | `{raised, %{name, led, first_time}}`.
  """
  def allowance(thread, max) when is_integer(max) do
    with name when is_binary(name) and max < @ceiling <- builder(thread),
         record = record(name),
         true <- earned?(record) do
      {max + 1, Map.put(record, :name, name)}
    else
      _ -> {max, nil}
    end
  end

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
