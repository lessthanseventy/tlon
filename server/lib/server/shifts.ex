defmodule Server.Shifts do
  @moduledoc """
  Day and night shifts on one bench. A seat is on the `day` shift, the `night` shift, or both
  (`all`, every seat until it is put on one, so a workspace with no shifts set works as it always
  has). The workspace is on one shift at a time, and `Server.Workspaces.bench/1` is the crew on
  shift, so staffing, intake and every restaff pick only from it. A shift change restaffs each open
  workline led by someone going off, the workline's own way (`Server.Workline.restaff_now/1`); a
  plain thread waits for its lead's shift.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspace
  alias Server.WorkspaceAgent
  alias Server.Workspaces

  @shifts ~w(day night)

  @doc "The workspace's shift, `day` or `night`."
  def current(workspace_id), do: Repo.one(from w in Workspace, where: w.id == ^workspace_id, select: w.shift) || "day"

  @doc """
  Put the workspace on shift `to`. Each open workline led by someone going off is restaffed from the
  crew coming on (`restaffed`); a plain thread they lead waits for them (`waiting`). Switching to the
  shift already on changes nothing. `{:ok, %{restaffed, waiting}}` | `{:error, :unknown_shift}`.
  """
  def switch(workspace_id, to) when to in @shifts do
    if current(workspace_id) == to do
      {:ok, %{restaffed: [], waiting: []}}
    else
      {1, _} = Repo.update_all(from(w in Workspace, where: w.id == ^workspace_id), set: [shift: to])
      announce(workspace_id)
      going = workspace_id |> Workspaces.bench_all() |> Enum.filter(&(&1.crew not in ["all", to]))

      {:ok, workspace_id |> led_by(going) |> Enum.reduce(%{restaffed: [], waiting: []}, &change_over(&1, &2, to))}
    end
  end

  def switch(_workspace_id, _to), do: {:error, :unknown_shift}

  @doc "Put a seat on a shift: `day`, `night` or `all` (both). `{:ok, seat}` | `{:error, changeset | :not_found}`."
  def assign(seat_id, crew) do
    with %WorkspaceAgent{} = seat <- Repo.get(WorkspaceAgent, seat_id) || {:error, :not_found},
         {:ok, seat} <- seat |> WorkspaceAgent.edit_changeset(%{crew: crew}) |> Repo.update() do
      announce(seat.workspace_id)
      {:ok, seat}
    end
  end

  defp announce(workspace_id), do: Server.Bus.broadcast({:workspace_edited, Repo.get!(Workspace, workspace_id)})

  defp led_by(_workspace_id, []), do: []

  defp led_by(workspace_id, going) do
    ids = Enum.map(going, & &1.agent_id)

    Repo.all(
      from t in Thread,
        where: t.workspace_id == ^workspace_id and t.state == "open" and t.agent_id in ^ids,
        order_by: t.id
    )
  end

  defp change_over(%Thread{stage: stage} = thread, acc, to) when stage not in [nil, "merged"] do
    note(thread, "#{mark(to)} the #{to} shift is on: whoever is on shift for #{stage} picks this workline up.")
    {:ok, _} = Server.Workline.restaff_now(thread)
    %{acc | restaffed: acc.restaffed ++ [thread.id]}
  end

  defp change_over(thread, acc, to) do
    note(thread, "#{mark(to)} the #{to} shift is on: this waits for its lead's shift.")
    %{acc | waiting: acc.waiting ++ [thread.id]}
  end

  defp mark("night"), do: "☾"
  defp mark("day"), do: "☀"

  defp note(thread, body), do: {:ok, _} = Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
end
