defmodule Server.Blocked do
  @moduledoc """
  A seat that cannot act because an open ticket is in the way (an infra fault someone already
  filed) says so with `blocked_on` instead of asking the operator. The block is a `blocked_on`
  tie between the thread and the ticket (`Server.TicketThread`): no column, and the ticket's own
  threads list shows who waits.

  A blocked thread is not nudged to continue (`Server.Workline.Continuation`) and is not a
  `stalled` Need; the ticket is one `blocked` Need however many threads wait on it
  (`Server.Office.Needs`).

  The block clears when the ticket is closed AND a release has gone live since: the fix reaches a
  seat's launch only at a cut, so `release/0` runs when `Server.Release.PM.note_live/1` says a new
  release is live, and wakes each blocked thread's lead to retry.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Ticket
  alias Server.TicketThread
  alias Server.Tickets

  @doc """
  Thread `thread_id`, by `agent`, is blocked on open ticket `ticket_id` because of `why`: `why` is
  appended to the ticket as seen again (its count rises like any recurrence), the thread is tied
  to it and says so in a notice. Asks nobody. `{:ok, ticket}` or `{:error, why}` for a ticket that
  is missing, not a plain ticket, or not open.
  """
  def declare(ticket_id, thread_id, agent, why) do
    case Tickets.get(ticket_id) do
      %Ticket{kind: "ticket", status: status} = ticket when status != "done" ->
        with {:ok, _} <- Tickets.tie(ticket, thread_id, "blocked_on"),
             {:ok, ticket} <- Server.Recurrence.ticket_seen(ticket_id, why, "#{agent}, thread #{thread_id}") do
          {:ok, _} =
            Channel.post(%{
              thread_id: thread_id,
              author: agent,
              kind: "notice",
              body:
                "blocked on ticket ##{ticket.id} (#{ticket.title}): #{String.trim(why)}. " <>
                  "Not asking the operator; the lead is woken when it is closed and a release is live."
            })

          {:ok, ticket}
        end

      %Ticket{kind: "ticket"} ->
        {:error, "ticket ##{ticket_id} is not open (done): file a new one, or ask the operator"}

      %Ticket{} ->
        {:error, "##{ticket_id} is an epic or initiative, not a ticket that can block work"}

      nil ->
        {:error, "no ticket ##{ticket_id}"}
    end
  end

  @doc "Whether the thread is blocked on a ticket: nothing is owed from it until `release/0` clears it."
  def blocked?(thread_id) do
    Repo.exists?(from tt in TicketThread, where: tt.thread_id == ^thread_id and tt.kind == "blocked_on")
  end

  @doc """
  Open tickets with open threads blocked on them: `[{ticket, [thread], at}]`, `at` the newest block
  (so a new seat hitting a put-away ticket brings its Need back).
  """
  def waiting do
    from(tt in TicketThread,
      join: tk in Ticket,
      on: tk.id == tt.ticket_id,
      join: t in Thread,
      on: t.id == tt.thread_id,
      where: tt.kind == "blocked_on" and tk.status != "done" and t.state == "open",
      order_by: [asc: tt.id],
      select: {tk, t, tt.created_at}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0).id)
    |> Enum.map(fn {_, [{tk, _, _} | _] = rows} ->
      {tk, Enum.map(rows, &elem(&1, 1)), rows |> Enum.map(&elem(&1, 2)) |> Enum.max(DateTime)}
    end)
  end

  @doc """
  Clear every block whose ticket is closed and tell the lead of each open thread so, as a post
  that wakes it. The number of blocks cleared.
  """
  def release do
    ties =
      Repo.all(
        from tt in TicketThread,
          join: tk in Ticket,
          on: tk.id == tt.ticket_id,
          where: tt.kind == "blocked_on" and tk.status == "done",
          select: {tt, tk}
      )

    for {tt, tk} <- ties do
      {:ok, _} = Repo.delete(tt)
      wake(tt.thread_id, tk)
    end

    length(ties)
  end

  defp wake(thread_id, ticket) do
    with %Thread{state: "open"} <- Repo.get(Thread, thread_id),
         lead when not is_nil(lead) <- Channel.thread_lead(thread_id) do
      Channel.post(%{
        thread_id: thread_id,
        author: "tlon",
        body:
          "@#{lead} the blocker ##{ticket.id} (#{ticket.title}) is closed and a release is live since: " <>
            "retry what it stopped."
      })
    end
  end
end
