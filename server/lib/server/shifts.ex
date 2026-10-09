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

  # Claude Code's own usage-limit line, anchored to how it prints it, so a pane that only talks
  # about limits never reads as out of quota
  @quota_out ~r/^\s*(⎿\s*)?(Claude usage limit reached|(5-hour|weekly|session) limit reached\b|You've hit your (usage )?limit\b)/miu

  @doc "The workspace's shift, `day` or `night`."
  def current(workspace_id), do: Repo.one(from w in Workspace, where: w.id == ^workspace_id, select: w.shift) || "day"

  @doc """
  Put the workspace on shift `to`. Each open workline led by someone going off is restaffed from the
  crew coming on (`restaffed`); a plain thread they lead waits for them (`waiting`). Switching to the
  shift already on changes nothing. `{:ok, %{restaffed, waiting}}` |
  `{:error, :unknown_shift | :not_found}`.
  """
  def switch(workspace_id, to) when to in @shifts do
    cond do
      is_nil(Repo.get(Workspace, workspace_id)) -> {:error, :not_found}
      current(workspace_id) == to -> {:ok, %{restaffed: [], waiting: []}}
      true -> switch_to(workspace_id, to)
    end
  end

  def switch(_workspace_id, _to), do: {:error, :unknown_shift}

  @doc """
  The crew a seat hired now joins: the shift on, once the workspace has crews; with none set, both,
  so a bench with no shifts stays without them.
  """
  def hire_crew(workspace_id) do
    if Enum.any?(Workspaces.bench_all(workspace_id), &(&1.crew != "all")), do: current(workspace_id), else: "all"
  end

  @doc "Whether a pane's text shows Claude Code's usage limit reached."
  def out_of_quota?(text) when is_binary(text), do: Regex.match?(@quota_out, text)

  @doc """
  A coworker's pane text, read by the attention sweep: Claude's usage limit reached on the day shift,
  with a night crew to come on, puts the night shift on and tells the lobby why (the board's `S` puts
  the day crew back after the reset). Once: on the night shift there is nothing to switch.
  `{:switched, "night"}` | `:ok`.
  """
  def quota_check(workspace_id, text) do
    with true <- out_of_quota?(text),
         "day" <- current(workspace_id),
         true <- Enum.any?(Workspaces.bench_all(workspace_id), &(&1.crew == "night")),
         {:ok, _} <- switch(workspace_id, "night") do
      reset = with [line] <- Regex.run(~r/reset[s]?[^\n]*/i, text), do: " (Claude says: #{String.trim(line)})"

      with %Thread{id: lobby} <- Channel.machine_thread(workspace_id),
           do:
             note(
               %Thread{id: lobby},
               "☾ Claude's usage limit is reached, so the night shift is on#{reset}. After the reset, the shift board's S puts the day crew back."
             )

      {:switched, "night"}
    else
      _ -> :ok
    end
  end

  @doc "Put a seat on a shift: `day`, `night` or `all` (both). `{:ok, seat}` | `{:error, changeset | :not_found}`."
  def assign(seat_id, crew) do
    with %WorkspaceAgent{} = seat <- Repo.get(WorkspaceAgent, seat_id) || {:error, :not_found},
         {:ok, seat} <- seat |> WorkspaceAgent.edit_changeset(%{crew: crew}) |> Repo.update() do
      announce(seat.workspace_id)
      {:ok, seat}
    end
  end

  defp switch_to(workspace_id, to) do
    {1, _} = Repo.update_all(from(w in Workspace, where: w.id == ^workspace_id), set: [shift: to])
    announce(workspace_id)
    going = workspace_id |> Workspaces.bench_all() |> Enum.filter(&(&1.crew not in ["all", to]))
    {:ok, workspace_id |> led_by(going) |> Enum.reduce(%{restaffed: [], waiting: []}, &change_over(&1, &2, to))}
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

  # restaffed only when the lead actually changed: with nobody of the kind on shift, restaff says so
  # itself and the workline waits
  defp change_over(%Thread{stage: stage} = thread, acc, to) when stage not in [nil, "merged"] do
    before = Channel.thread_lead(thread.id)
    {:ok, _} = Server.Workline.restaff_now(thread)

    if Channel.thread_lead(thread.id) == before do
      %{acc | waiting: acc.waiting ++ [thread.id]}
    else
      note(thread, "#{mark(to)} the #{to} shift is on: the crew on shift picks this workline up at #{stage}.")
      %{acc | restaffed: acc.restaffed ++ [thread.id]}
    end
  end

  defp change_over(thread, acc, to) do
    note(thread, "#{mark(to)} the #{to} shift is on: this waits for its lead's shift.")
    %{acc | waiting: acc.waiting ++ [thread.id]}
  end

  defp mark("night"), do: "☾"
  defp mark("day"), do: "☼"

  defp note(thread, body), do: {:ok, _} = Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
end
