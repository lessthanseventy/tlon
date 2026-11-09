defmodule Server.Workline.Shared do
  @moduledoc """
  What the workline modules share: the stage brief posted on a thread, a move back to an earlier
  stage (`move_back/6`, and `bounce/4` on the same branch with a finding) and the operator's handle.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Staffing

  @doc false
  def bounce(thread, why, headline, by \\ nil) do
    {:ok, _} =
      move_back(
        thread,
        "build",
        why,
        "↩ back to build — #{headline}, then advance_stage; it comes back through verify and review.",
        fn _ -> :ok end,
        by
      )

    {:error, {:bounced, why}}
  end

  # The brief IS the wake: a server-authored message rides the lead-wake path (slice 2).
  # Best-effort — a post failure never blocks the (already durable) transition.
  @doc false
  def post_brief(thread, body) do
    Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # back to `to` on the same thread and branch: the stage and its ledger row in one write, the
  # stage's lead staffed and handed `brief`. `allowed` is judged on the row locked FOR UPDATE, the
  # lock the landing reads it under (`Server.Jobs.Land`), so a landing starting at the same instant
  # either sees the move or is seen by `allowed`. `by`, the seat that moved it back, is recorded for
  # the diary; nil when the machine did.
  @doc false
  def move_back(thread, to, why, brief, allowed, by) do
    fn ->
      locked = Repo.one!(from t in Thread, where: t.id == ^thread.id, lock: "FOR UPDATE")

      case allowed.(locked) do
        :ok ->
          {:ok, back} = locked |> Thread.workline_stage_changeset(%{stage: to, awaiting: nil}) |> Repo.update()

          {:ok, _event} =
            Dossier.record_event(%{
              thread_id: thread.id,
              kind: "stage_advanced",
              correlation: "workline:#{thread.slug}",
              detail: %{"from" => locked.stage, "to" => to, "bounced" => why, "by" => by}
            })

          back

        {:error, refusal} ->
          Repo.rollback(refusal)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, back} ->
        back = Staffing.restaff(back)
        Server.Bus.broadcast({:workline_advanced, back})
        post_brief(back, brief)
        {:ok, back}

      {:error, refusal} ->
        {:error, refusal}
    end
  end

  @doc false
  def operator, do: Server.OperatorConfig.operator()
end
