defmodule Server.Workline.Ledger do
  @moduledoc """
  The value ledger (worklines slice 6): a READ-MODEL over rows the stage machine already
  writes — stage_advanced events + workline threads. The playbook's indicators come out of
  coordination as a side effect, never a second telemetry system. `mise run server:ledger`.
  """

  import Ecto.Query

  alias Server.Event
  alias Server.Repo
  alias Server.Thread

  @doc "Every workline with its transitions, plus the tallies."
  def report do
    threads = Repo.all(from t in Thread, where: not is_nil(t.stage), order_by: [asc: t.id])

    by_thread =
      from(e in Event, where: e.kind == "stage_advanced", order_by: [asc: e.id])
      |> Repo.all()
      |> Enum.group_by(& &1.thread_id)

    worklines =
      Enum.map(threads, fn t ->
        transitions =
          for e <- Map.get(by_thread, t.id, []),
              do: %{from: e.detail["from"], to: e.detail["to"], at: e.created_at}

        %{
          id: t.id,
          slug: t.slug,
          title: t.title,
          stage: t.stage,
          awaiting: t.awaiting,
          born: t.born,
          opened_at: t.created_at,
          transitions: transitions
        }
      end)

    %{
      worklines: worklines,
      summary: %{
        open: Enum.count(worklines, &(&1.stage != "merged")),
        merged: Enum.count(worklines, &(&1.stage == "merged")),
        gated: Enum.count(worklines, & &1.awaiting)
      }
    }
  end

  @doc "The human-readable ledger."
  def render(%{worklines: []}), do: ~s(no worklines yet — open one: mise run server:cli -- workline "<title>" <slug>)

  def render(%{worklines: worklines, summary: s}) do
    lines =
      Enum.map(worklines, fn w ->
        gate = if w.awaiting, do: " ⏸awaiting #{w.awaiting}", else: ""
        born = if w.born == "machine", do: " (machine-born)", else: ""
        "##{w.id} #{w.slug} · #{w.stage}#{gate}#{born} · #{length(w.transitions)} advances · opened #{date(w.opened_at)}"
      end)

    Enum.join(lines, "\n") <> "\n#{s.open} open · #{s.merged} merged · #{s.gated} gated"
  end

  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")
  defp date(_at), do: "?"

  @doc """
  Every open workline's live status (console panel read-model), in id order — see `status_for/1`.
  `workspace_id` scopes to one workspace's worklines; `nil` is every workspace.
  """
  def statuses(workspace_id \\ nil) do
    Thread
    |> where([t], not is_nil(t.stage))
    |> scope_workspace(workspace_id)
    |> order_by([t], asc: t.id)
    |> Repo.all()
    |> Enum.map(&status_for/1)
  end

  defp scope_workspace(query, nil), do: query
  defp scope_workspace(query, workspace_id), do: where(query, [t], t.workspace_id == ^workspace_id)

  @doc """
  One workline's live status (console panel read-model): stage, gate, and `blocking` — the
  cmd/tail of the LATEST verify-stage check when it's a `check_failed`, `nil` when the
  latest is a pass or no verify check has run yet. Read fresh, not cached — the check state
  can flip between panel renders.
  """
  def status_for(%Thread{} = t) do
    %{
      id: t.id,
      slug: t.slug,
      title: t.title,
      stage: t.stage,
      awaiting: t.awaiting,
      blocking: blocking_check(t)
    }
  end

  defp blocking_check(t) do
    correlation = "workline:#{t.slug}:verify"

    latest =
      Repo.one(
        from(e in Event,
          where: e.thread_id == ^t.id and e.correlation == ^correlation and e.kind in ["check_passed", "check_failed"],
          order_by: [desc: e.id],
          limit: 1
        )
      )

    case latest do
      %Event{kind: "check_failed", detail: detail} -> %{cmd: detail["cmd"], tail: detail["tail"]}
      _ -> nil
    end
  end
end
