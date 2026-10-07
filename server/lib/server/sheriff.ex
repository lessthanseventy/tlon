defmodule Server.Sheriff do
  @moduledoc """
  The coworker who owns red. A workspace's sheriff (bench archetype `sheriff`) is told of every red
  signal — a red verify, a landing the merge queue bounced, a workline stuck out of nudges, a failed
  schedule run — on its beat: one standing thread per workspace, led by the sheriff, opened the
  first time it is needed. Each report says what broke, on which thread, and the post wakes the
  sheriff to triage it: hand the lead the fix, raise a flake as an issue to fix (never waive it),
  fix small infra, and bring the operator only what is theirs to decide.

  A workspace with no sheriff on its bench gets nothing here; its red verifies stay on the
  operator's list (`Server.Office.Needs`) instead.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread

  @beat "sheriff's beat"

  @doc "The workspace's sheriff on its bench, or nil."
  def of(workspace_id) when is_integer(workspace_id),
    do: workspace_id |> Server.Workspaces.bench() |> Enum.find(&(&1.archetype == "sheriff"))

  def of(_workspace_id), do: nil

  @doc """
  Tell `source`'s workspace's sheriff that `what` went red on it. `source` is a thread (or a map with
  its `id`, `title` and `workspace_id`). Never raises — a report must not break the red path that
  makes it. `:ok`, or `:no_sheriff`.
  """
  def report(source, what) do
    case of(source.workspace_id) do
      nil ->
        :no_sheriff

      sheriff ->
        with {:ok, beat} <- beat(source.workspace_id, sheriff.name) do
          Channel.post(%{thread_id: beat.id, author: "tlon", body: "🚨 ##{source.id} #{source.title}: #{what}"})
        end

        :ok
    end
  rescue
    e ->
      require Logger

      Logger.warning("sheriff report for ##{inspect(Map.get(source, :id))} failed: #{Exception.message(e)}")
      :ok
  end

  defp beat(workspace_id, sheriff) do
    case Repo.one(
           from t in Thread,
             where: t.workspace_id == ^workspace_id and t.title == @beat and t.state == "open",
             order_by: [desc: t.id],
             limit: 1
         ) do
      %Thread{} = t ->
        {:ok, t}

      nil ->
        with {:ok, t} <- Channel.open_thread(%{title: @beat, workspace_id: workspace_id, scope: "machine"}),
             {:ok, _} <- Channel.assign_lead(t.id, sheriff) do
          {:ok, t}
        end
    end
  end
end
