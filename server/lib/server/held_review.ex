defmodule Server.HeldReview do
  @moduledoc """
  The PM's weekly review of held tickets: one post on each workspace's standing thread listing the
  tickets labelled `held` that nobody has touched in #{30} days, with the three answers in words. It is
  a post, not a Need or a gate. Run Monday morning (`Server.Jobs.HeldReview`).
  """
  import Ecto.Query

  alias Server.{Channel, Repo, Ticket}

  @stale_days 30

  @doc "Post the review for every workspace with a PM and stale held tickets; how many were posted."
  @spec run(DateTime.t()) :: non_neg_integer()
  def run(now \\ DateTime.utc_now()) do
    from(w in Server.Workspace, select: w.id)
    |> Repo.all()
    |> Enum.count(&review(&1, now))
  end

  defp review(ws, now) do
    with %{} <- ws |> Server.Workspaces.bench() |> Enum.find(&(&1.archetype == "pm")),
         %Server.Thread{id: thread_id} <- Channel.machine_thread(ws),
         [_ | _] = held <- stale(ws, now) do
      {:ok, _} = Channel.post(%{thread_id: thread_id, author: "tlon", kind: "notice", body: body(held, now)})
      true
    else
      _ -> false
    end
  end

  defp stale(ws, now) do
    cutoff = DateTime.add(now, -@stale_days, :day)

    from(t in Ticket,
      where: t.workspace_id == ^ws and t.kind == "ticket" and t.status != "done" and t.updated_at < ^cutoff,
      order_by: t.updated_at
    )
    |> Repo.all()
    |> Enum.filter(&Server.Intake.held?/1)
  end

  defp body(held, now) do
    lines = Enum.map_join(held, "\n", &"##{&1.id} #{&1.title}, held #{DateTime.diff(now, &1.updated_at, :day)} days")

    """
    Held for #{@stale_days}+ days, #{length(held)}:
    #{lines}

    Each has three answers. Keep: nothing to do, it stays held. Close: `ticket-set <id> status done`. \
    Unhold: drop the `held` label with `update_ticket` (`labels` without `held`) so intake can take it.\
    """
  end
end
