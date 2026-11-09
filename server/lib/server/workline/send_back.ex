defmodule Server.Workline.SendBack do
  @moduledoc """
  A workline's move backwards: `send_back/5` and the rules for who may send it where, and while what.
  """

  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Review
  alias Server.Workline.Shared

  @stages ~w(intent spec plan build verify review landed)

  @doc """
  Send `thread` back to an earlier working stage (`spec`, `plan` or `build`) on the same thread and
  branch: what was built and reviewed stays, and the stage's lead is told to improve it, not redo
  it. Back to build is the call of the workline's lead (its reviewer, QA or builder), or Uqbar's at a
  gate parked on the operator whose grade hit no limit (`limit_hit?/1`); back to plan or
  spec reshapes the build, a coherence call, so it is the tech lead's (`Server.Coworker.lead/1`) or
  the operator's. An open workline only, and not while its verify or landing is queued or running:
  either would move it on from under the send-back. With `unqueue: true` a landing that is queued but
  not yet running is pulled from the merge queue in the same transaction as the move, so nothing
  finds the thread at review to requeue it (`requeue_stranded/0`); a running landing, and a verify
  in any state, still refuse. `{:ok, thread}` | `{:error, {:not_movable, stage}}` | `{:error,
  {:in_flight, why}}` | `{:error, {:not_behind, stage}}` | `{:error, {:not_yours, why}}`.
  """
  def send_back(%Thread{} = thread, to, why, by, opts \\ []) do
    unqueue? = Keyword.get(opts, :unqueue, false)

    allowed = fn locked ->
      with :ok <- movable(locked),
           :ok <- not_in_flight(locked, unqueue?),
           :ok <- behind(locked, to),
           :ok <- may_send_back(locked, to, by),
           do: pull_landing(locked, unqueue?)
    end

    Shared.move_back(thread, to, "sent back by #{by}: #{why}", send_back_brief(to, why, by), allowed, by)
  end

  defp behind(%Thread{stage: stage}, to) do
    index = &Enum.find_index(@stages, fn s -> s == &1 end)

    if to in ~w(spec plan build) and stage in @stages and index.(to) < index.(stage),
      do: :ok,
      else: {:error, {:not_behind, to}}
  end

  defp may_send_back(thread, to, by) do
    tech = tech_lead(thread)

    cond do
      by == Shared.operator() or by == tech ->
        :ok

      to == "build" ->
        may_send_to_build(thread, by)

      true ->
        {:error,
         {:not_yours,
          "back to #{to} is the tech lead's call: say why on the thread and @#{tech || Shared.operator()}, who decides"}}
    end
  end

  defp may_send_to_build(thread, "uqbar"), do: uqbar_may_send_back(thread)

  defp may_send_to_build(thread, by) do
    case Server.Channel.thread_lead(thread.id) do
      ^by ->
        :ok

      lead ->
        {:error,
         {:not_yours, "only ##{thread.id}'s lead (#{lead}), the tech lead or the operator sends it back to build"}}
    end
  end

  defp uqbar_may_send_back(thread) do
    cond do
      Review.limit_hit?(thread) ->
        {:error, {:not_yours, "##{thread.id}'s grade hit a limit: its gate is the operator's"}}

      thread.awaiting != Shared.operator() ->
        {:error, {:not_yours, "##{thread.id} is not parked on the operator's gate"}}

      true ->
        :ok
    end
  end

  defp tech_lead(%Thread{workspace_id: nil}), do: nil

  defp tech_lead(%Thread{workspace_id: ws}) do
    ws
    |> Server.Workspaces.bench()
    |> Server.Coworker.lead()
    |> case do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp send_back_brief("build", why, by),
    do:
      "↩ back to build — sent back by #{by}: #{why}. The branch keeps the build and its review: fix what's named, then advance_stage; it comes back through verify and review."

  defp send_back_brief(to, why, by),
    do:
      "↩ back to #{to} — sent back by #{by}: #{why}. The branch keeps the build and review.md: revise #{to}.md to say what changes and what stays, so the build is improved, not redone; then advance_stage."

  defp movable(%Thread{state: "open", stage: stage}) when stage in ~w(plan build verify review), do: :ok
  defp movable(%Thread{stage: stage}), do: {:error, {:not_movable, stage}}

  # With `unqueue?` only a verify or a landing already executing blocks; a landing still waiting its
  # turn is `cancel_landings/1`'s to pull.
  defp not_in_flight(thread, unqueue?) do
    blocking =
      thread
      |> in_flight_jobs(["available", "scheduled", "executing", "retryable"])
      |> Enum.filter(fn {queue, state, _id} -> not unqueue? or queue == "verify" or state == "executing" end)

    case blocking do
      [] ->
        :ok

      [{q, _, _} | _] ->
        {:error,
         {:in_flight, "its #{if q == "verify", do: "verify", else: "landing"} is queued or running; let it finish"}}
    end
  end

  defp in_flight_jobs(thread, states) do
    Repo.all(
      from j in Oban.Job,
        where:
          j.queue in ["verify", "landing"] and j.state in ^states and
            fragment("?->>'thread_id'", j.args) == ^to_string(thread.id),
        select: {j.queue, j.state, j.id}
    )
  end

  defp pull_landing(_thread, false), do: :ok
  defp pull_landing(thread, true), do: cancel_landings(thread)

  # Inside move_back's transaction, under the thread row's lock. The one window left: a landing that
  # starts executing between not_in_flight's select and this cancel — Land takes the same row lock
  # (`Server.Jobs.Land.perform/1`), so it waits on us, then finds the thread moved and does nothing.
  defp cancel_landings(thread) do
    thread
    |> in_flight_jobs(["available", "scheduled", "retryable"])
    |> Enum.reduce_while(:ok, fn
      {"landing", _state, id}, :ok ->
        case Server.Jobs.cancel(id) do
          :ok ->
            {:cont, :ok}

          {:error, why} ->
            {:halt, {:error, {:in_flight, "its landing is queued and can't be pulled here: #{inspect(why)}"}}}
        end

      _verify, :ok ->
        {:cont, :ok}
    end)
  end
end
